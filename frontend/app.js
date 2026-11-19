// AgentPass frontend logic (vanilla JS + ethers v6 via CDN).
// No QR login, no pairing codes, no stored sessions: the user connects their own
// injected wallet (MetaMask/Rabby) and confirms every transaction themselves.

let abi = null;
let readProvider = null;
let readContract = null;
let signer = null;
let signerContract = null;
let account = null;
let isHolder = false;

const $ = (id) => document.getElementById(id);
const short = (a) => (a ? a.slice(0, 6) + "…" + a.slice(-4) : "");
const fmtTime = (ts) => new Date(Number(ts) * 1000).toLocaleString();

function setStatus(msg) {
  $("status").textContent = msg;
}

async function init() {
  $("networkName").textContent = CONFIG.chainName + " (chain " + CONFIG.chainId + ")";
  $("contractAddr").textContent = CONFIG.agentPassAddress;
  if (typeof ethers === "undefined") {
    $("events").textContent = "Failed to load the ethers.js library (CDN). Check your connection and reload.";
    return;
  }
  try {
    const res = await fetch("abi.json");
    abi = await res.json();
  } catch (e) {
    $("events").textContent = "Failed to load contract ABI (abi.json).";
    return;
  }
  readProvider = new ethers.JsonRpcProvider(CONFIG.rpcUrl);
  if (CONFIG.agentPassAddress === "0x0000000000000000000000000000000000000000") {
    $("events").innerHTML =
      '<span class="meta">Contract not deployed yet on this network — the address will appear here after deploy.</span>';
    return;
  }
  readContract = new ethers.Contract(CONFIG.agentPassAddress, abi, readProvider);
  await loadEvents();
  $("connectBtn").addEventListener("click", connect);
  $("createForm").addEventListener("submit", onCreateEvent);
}

async function loadEvents() {
  const box = $("events");
  try {
    const total = Number(await readContract.totalEvents());
    if (total === 0) {
      box.innerHTML = '<span class="meta">No events yet. Be the first to create one below.</span>';
      return;
    }
    box.innerHTML = "";
    const now = Math.floor(Date.now() / 1000);
    for (let id = total; id >= 1; id--) {
      const ev = await readContract.getEvent(id);
      const card = document.createElement("div");
      card.className = "card";
      const state = now < Number(ev.startTime)
        ? "Upcoming"
        : now <= Number(ev.endTime)
        ? "Live"
        : "Ended";
      const left = Number(ev.maxSupply) - Number(ev.minted);
      card.innerHTML =
        "<h3>" + escapeHtml(ev.name) + ' <span class="pill">' + state + "</span></h3>" +
        "<p>" + escapeHtml(ev.description || "") + "</p>" +
        '<p class="meta">Event #' + id + " · Organizer " + short(ev.organizer) +
        " · Claim window: " + fmtTime(ev.startTime) + " → " + fmtTime(ev.endTime) +
        "<br>Badges: " + ev.minted + " / " + ev.maxSupply + " claimed (" + left + " left)" +
        (ev.metadataURI ? "<br>Metadata: " + escapeHtml(ev.metadataURI) : "") + "</p>";
      const btn = document.createElement("button");
      btn.textContent = "Claim badge";
      btn.dataset.eventId = String(id);
      btn.disabled = true;
      btn.title = "Connect a wallet holding an Agent ID to claim.";
      btn.addEventListener("click", () => onClaim(id, btn));
      card.appendChild(btn);
      const note = document.createElement("span");
      note.className = "meta";
      note.style.marginLeft = "10px";
      note.id = "note-" + id;
      card.appendChild(note);
      box.appendChild(card);
    }
    await refreshClaimStates();
  } catch (e) {
    box.textContent = "Failed to load events: " + (e && e.message ? e.message : e);
  }
}

async function refreshClaimStates() {
  if (!readContract) return;
  const total = Number(await readContract.totalEvents());
  const now = Math.floor(Date.now() / 1000);
  for (let id = 1; id <= total; id++) {
    const btn = document.querySelector('button[data-event-id="' + id + '"]');
    const note = $("note-" + id);
    if (!btn || !note) continue;
    const ev = await readContract.getEvent(id);
    const live = now >= Number(ev.startTime) && now <= Number(ev.endTime);
    const left = Number(ev.maxSupply) - Number(ev.minted);
    if (!account) {
      btn.disabled = true;
      note.textContent = "Connect wallet to claim.";
    } else if (!isHolder) {
      btn.disabled = true;
      note.textContent = "This wallet holds no Agent ID.";
    } else if (!live) {
      btn.disabled = true;
      note.textContent = now < Number(ev.startTime) ? "Claim opens " + fmtTime(ev.startTime) + "." : "Claim window closed.";
    } else if (left <= 0) {
      btn.disabled = true;
      note.textContent = "Sold out.";
    } else {
      const claimed = await readContract.hasClaimed(id, account);
      if (claimed) {
        btn.disabled = true;
        note.textContent = "You already claimed this badge.";
      } else {
        btn.disabled = false;
        note.textContent = "You can claim this badge (free, gas only).";
      }
    }
  }
}

async function connect() {
  if (!window.ethereum) {
    setStatus("No injected wallet found. Install MetaMask or Rabby, then reload.");
    return;
  }
  try {
    const provider = new ethers.BrowserProvider(window.ethereum);
    const accounts = await provider.send("eth_requestAccounts", []);
    account = accounts[0];
    const net = await provider.getNetwork();
    if (Number(net.chainId) !== CONFIG.chainId) {
      try {
        await window.ethereum.request({
          method: "wallet_switchEthereumChain",
          params: [{ chainId: CONFIG.chainHex }],
        });
      } catch (switchErr) {
        if (switchErr && switchErr.code === 4902) {
          await window.ethereum.request({
            method: "wallet_addEthereumChain",
            params: [{
              chainId: CONFIG.chainHex,
              chainName: CONFIG.chainName,
              rpcUrls: [CONFIG.rpcUrl],
              blockExplorerUrls: [CONFIG.explorer],
              nativeCurrency: { name: "BNB", symbol: "BNB", decimals: 18 },
            }],
          });
        } else {
          throw switchErr;
        }
      }
    }
    signer = await provider.getSigner();
    signerContract = new ethers.Contract(CONFIG.agentPassAddress, abi, signer);
    const registry = new ethers.Contract(
      CONFIG.agentIdRegistryAddress,
      ["function balanceOf(address) view returns (uint256)"],
      provider
    );
    const bal = await registry.balanceOf(account);
    isHolder = bal > 0n;
    $("accountInfo").textContent = "Connected: " + short(account);
    const st = $("agentIdStatus");
    st.textContent = isHolder ? "Agent ID: yes" : "Agent ID: no";
    st.className = isHolder ? "badge-ok" : "badge-no";
    setStatus(isHolder
      ? "Connected. You hold an Agent ID — you can claim badges."
      : "Connected, but this wallet holds no Agent ID. Claim an Agent ID in the Binance App first.");
    await refreshClaimStates();
    await loadMyBadges();
  } catch (e) {
    setStatus("Connection failed: " + (e && e.message ? e.message : e));
  }
}

async function onClaim(eventId, btn) {
  if (!signerContract) return;
  btn.disabled = true;
  setStatus("Waiting for you to confirm the claim in your wallet…");
  try {
    const tx = await signerContract.claim(eventId);
    setStatus("Claim submitted: " + tx.hash + " — waiting for confirmation…");
    const receipt = await tx.wait();
    if (receipt.status === 1) {
      setStatus("Badge claimed! Tx: " + tx.hash);
    } else {
      setStatus("Claim transaction failed on-chain: " + tx.hash);
    }
  } catch (e) {
    setStatus("Claim failed or rejected: " + (e && e.reason ? e.reason : e.message || e));
  }
  await loadEvents();
  await loadMyBadges();
}

async function loadMyBadges() {
  const box = $("myBadges");
  if (!account || !readContract) return;
  try {
    const total = Number(await readContract.totalMinted());
    const mine = [];
    for (let tokenId = 1; tokenId <= total; tokenId++) {
      const owner = await readContract.ownerOf(tokenId);
      if (owner.toLowerCase() === account.toLowerCase()) {
        const eventId = Number(await readContract.tokenEvent(tokenId));
        const ev = await readContract.getEvent(eventId);
        mine.push({ tokenId, eventId, name: ev.name });
      }
    }
    if (mine.length === 0) {
      box.innerHTML = '<span class="meta">No badges yet — claim one from an event above.</span>';
      return;
    }
    box.innerHTML = mine.map((b) =>
      '<div class="card"><h3>Badge #' + b.tokenId + " — " + escapeHtml(b.name) + "</h3>" +
      '<p class="meta">Event #' + b.eventId + " · Soulbound (non-transferable)</p></div>"
    ).join("");
  } catch (e) {
    box.textContent = "Failed to load badges: " + (e && e.message ? e.message : e);
  }
}

async function onCreateEvent(e) {
  e.preventDefault();
  if (!signerContract) {
    setStatus("Connect your wallet first (it must hold an Agent ID).");
    return;
  }
  const name = $("evName").value.trim();
  const desc = $("evDesc").value.trim();
  const start = Math.floor(new Date($("evStart").value).getTime() / 1000);
  const end = Math.floor(new Date($("evEnd").value).getTime() / 1000);
  const supply = Number($("evSupply").value);
  const meta = $("evMeta").value.trim();
  if (!name || !start || !end || !supply) {
    setStatus("Please fill in all required fields.");
    return;
  }
  setStatus("Waiting for you to confirm event creation in your wallet…");
  try {
    const tx = await signerContract.createEvent(name, desc, start, end, supply, meta);
    setStatus("Event creation submitted: " + tx.hash + " — waiting for confirmation…");
    const receipt = await tx.wait();
    if (receipt.status === 1) {
      setStatus("Event created! Tx: " + tx.hash);
      $("createForm").reset();
    } else {
      setStatus("Event creation failed on-chain: " + tx.hash);
    }
  } catch (err) {
    setStatus("Event creation failed or rejected: " + (err && err.reason ? err.reason : err.message || err));
  }
  await loadEvents();
}

function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]));
}

document.addEventListener("DOMContentLoaded", init);
