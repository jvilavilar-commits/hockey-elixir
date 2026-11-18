(() => {
  "use strict";

  const canvas = document.getElementById("rink");
  const ctx = canvas.getContext("2d");
  const ui = {
    blueScore: document.getElementById("blueScore"), redScore: document.getElementById("redScore"),
    clock: document.getElementById("clock"), playerCount: document.getElementById("playerCount"),
    playerList: document.getElementById("playerList"), badge: document.getElementById("connectionBadge"),
    connectionText: document.getElementById("connectionText"), overlay: document.getElementById("overlay"),
    overlayKicker: document.getElementById("overlayKicker"), overlayTitle: document.getElementById("overlayTitle"),
    overlayMessage: document.getElementById("overlayMessage"), waitingDots: document.getElementById("waitingDots"),
    rematch: document.getElementById("rematchButton"), identityCard: document.getElementById("identityCard"),
    identityText: document.getElementById("identityText")
  };

  let socket;
  let reconnectTimer;
  let playerId = null;
  let game = null;
  let renderGame = null;
  let connectionAttempts = 0;
  const input = { up: false, down: false, left: false, right: false, kick: false };

  const keyMap = {
    KeyW: "up", ArrowUp: "up", KeyS: "down", ArrowDown: "down",
    KeyA: "left", ArrowLeft: "left", KeyD: "right", ArrowRight: "right", Space: "kick"
  };

  function connect() {
    clearTimeout(reconnectTimer);
    setConnection("connecting", connectionAttempts ? "Reconectando" : "Conectando");
    const protocol = location.protocol === "https:" ? "wss:" : "ws:";
    const token = sessionStorage.getItem("neon_rink_token") || "";
    socket = new WebSocket(`${protocol}//${location.host}/socket?token=${encodeURIComponent(token)}`);

    socket.addEventListener("open", () => { connectionAttempts = 0; setConnection("online", "En línea"); });
    socket.addEventListener("message", ({ data }) => {
      const message = JSON.parse(data);
      if (message.type === "welcome") {
        playerId = message.player_id;
        sessionStorage.setItem("neon_rink_token", message.token);
        game = message.state;
        renderGame = structuredClone(game);
        updateUI();
      } else if (message.type === "state") {
        game = message;
        if (!renderGame) renderGame = structuredClone(game);
        updateUI();
      } else if (message.type === "error" && message.reason === "room_full") {
        showOverlay("SALA COMPLETA", "Partida en curso", "Ya hay cuatro puestos ocupados. Inténtalo cuando quede una plaza.", false);
      }
    });
    socket.addEventListener("close", () => {
      setConnection("offline", "Sin conexión");
      showOverlay("CONEXIÓN INTERRUMPIDA", "Volviendo a la pista…", "Tu puesto está reservado. La partida permanecerá pausada mientras reconectamos.", false);
      connectionAttempts += 1;
      reconnectTimer = setTimeout(connect, Math.min(1000 * 2 ** connectionAttempts, 8000));
    });
    socket.addEventListener("error", () => socket.close());
  }

  function setConnection(status, text) {
    ui.badge.className = `connection-badge ${status}`;
    ui.connectionText.textContent = text;
  }

  function send(message) {
    if (socket?.readyState === WebSocket.OPEN) socket.send(JSON.stringify(message));
  }

  function sendInput() { send({ type: "input", input }); }

  window.addEventListener("keydown", (event) => {
    const action = keyMap[event.code];
    if (!action) return;
    event.preventDefault();
    if (!input[action]) { input[action] = true; sendInput(); }
  });

  window.addEventListener("keyup", (event) => {
    const action = keyMap[event.code];
    if (!action) return;
    event.preventDefault();
    if (input[action]) { input[action] = false; sendInput(); }
  });

  window.addEventListener("blur", () => {
    Object.keys(input).forEach((key) => input[key] = false);
    sendInput();
  });

  ui.rematch.addEventListener("click", () => send({ type: "rematch" }));

  function updateUI() {
    if (!game) return;
    ui.blueScore.textContent = game.score.blue;
    ui.redScore.textContent = game.score.red;
    const seconds = Math.max(0, Math.ceil(game.time_left));
    ui.clock.textContent = `${String(Math.floor(seconds / 60)).padStart(2, "0")}:${String(seconds % 60).padStart(2, "0")}`;
    ui.playerCount.textContent = `${game.connected_count} / 4`;
    renderPlayerList();

    if (playerId) {
      const me = game.players[String(playerId)];
      ui.identityCard.classList.remove("hidden");
      ui.identityText.textContent = me ? `${me.team === "blue" ? "Equipo azul" : "Equipo rojo"} · jugador ${me.number}` : "Reconectando";
    }

    switch (game.phase) {
      case "waiting":
        showOverlay("ESPERANDO JUGADORES", `${game.connected_count} de 4 listos`, "La partida de tres minutos comienza automáticamente cuando se llenen los cuatro puestos.", false);
        fillWaitingDots(game.connected_count);
        break;
      case "paused":
        showOverlay("PARTIDA EN PAUSA", "Falta un jugador", "El cronómetro está detenido. Continuaremos automáticamente cuando recupere la conexión.", false);
        fillWaitingDots(game.connected_count);
        break;
      case "goal_pause":
        showOverlay("¡GOL!", game.last_goal === "blue" ? "Punto para el azul" : "Punto para el rojo", "Recolocando a los jugadores…", false);
        break;
      case "finished": {
        const title = game.winner === "draw" ? "Empate" : `Gana el equipo ${game.winner === "blue" ? "azul" : "rojo"}`;
        showOverlay("FINAL DE LA PARTIDA", title, `Resultado: ${game.score.blue} — ${game.score.red}.`, true);
        break;
      }
      case "playing": hideOverlay(); break;
    }
  }

  function renderPlayerList() {
    const rows = [];
    for (let id = 1; id <= 4; id += 1) {
      const player = game.players[String(id)];
      if (!player) {
        rows.push(`<div class="player-row empty-slot"><span class="player-icon">${id}</span><span class="player-copy"><strong>Puesto libre</strong><span>Esperando conexión</span></span></div>`);
        continue;
      }
      const classes = ["player-row", player.id === playerId ? "me" : "", player.connected ? "" : "disconnected"].join(" ");
      rows.push(`<div class="${classes}"><span class="player-icon ${player.team}">${player.number}</span><span class="player-copy"><strong>${player.id === playerId ? "Tú" : `Jugador ${player.id}`}</strong><span>Equipo ${player.team === "blue" ? "azul" : "rojo"}</span></span><i class="player-status"></i></div>`);
    }
    ui.playerList.innerHTML = rows.join("");
  }

  function showOverlay(kicker, title, message, rematch) {
    ui.overlayKicker.textContent = kicker;
    ui.overlayTitle.textContent = title;
    ui.overlayMessage.textContent = message;
    ui.overlay.classList.add("visible");
    ui.rematch.classList.toggle("hidden", !rematch);
    ui.waitingDots.classList.toggle("hidden", rematch || kicker === "¡GOL!");
  }

  function hideOverlay() { ui.overlay.classList.remove("visible"); }
  function fillWaitingDots(count) {
    [...ui.waitingDots.children].forEach((dot, index) => dot.classList.toggle("filled", index < count));
  }

  function interpolate() {
    if (!game || !renderGame) return;
    for (const [id, target] of Object.entries(game.players)) {
      if (!renderGame.players[id]) renderGame.players[id] = { ...target };
      renderGame.players[id].x += (target.x - renderGame.players[id].x) * 0.32;
      renderGame.players[id].y += (target.y - renderGame.players[id].y) * 0.32;
    }
    renderGame.puck.x += (game.puck.x - renderGame.puck.x) * 0.38;
    renderGame.puck.y += (game.puck.y - renderGame.puck.y) * 0.38;
  }

  function draw() {
    requestAnimationFrame(draw);
    interpolate();
    drawRink();
    if (!renderGame) return;
    Object.values(renderGame.players).forEach(drawPlayer);
    drawPuck(renderGame.puck);
  }

  function drawRink() {
    const g = ctx.createLinearGradient(0, 0, 1000, 600);
    g.addColorStop(0, "#dff5f0"); g.addColorStop(.5, "#cce9e7"); g.addColorStop(1, "#dcf1ec");
    ctx.fillStyle = g; ctx.fillRect(0, 0, 1000, 600);
    ctx.save(); ctx.globalAlpha = .11; ctx.strokeStyle = "#39717d"; ctx.lineWidth = 1;
    for (let x = -600; x < 1200; x += 46) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x + 600, 600); ctx.stroke(); }
    ctx.restore();

    ctx.fillStyle = "rgba(15, 69, 80, .08)"; ctx.fillRect(0, 0, 24, 600); ctx.fillRect(976, 0, 24, 600);
    ctx.strokeStyle = "#568b92"; ctx.lineWidth = 5; ctx.strokeRect(24, 24, 952, 552);
    ctx.strokeStyle = "rgba(13, 110, 149, .55)"; ctx.lineWidth = 4; ctx.beginPath(); ctx.moveTo(334, 25); ctx.lineTo(334, 575); ctx.moveTo(666, 25); ctx.lineTo(666, 575); ctx.stroke();
    ctx.strokeStyle = "rgba(213, 39, 69, .7)"; ctx.beginPath(); ctx.moveTo(500, 25); ctx.lineTo(500, 575); ctx.stroke();
    ctx.beginPath(); ctx.arc(500, 300, 72, 0, Math.PI * 2); ctx.stroke();
    ctx.fillStyle = "rgba(213, 39, 69, .7)"; ctx.beginPath(); ctx.arc(500, 300, 6, 0, Math.PI * 2); ctx.fill();

    drawFaceoff(250, 180); drawFaceoff(250, 420); drawFaceoff(750, 180); drawFaceoff(750, 420);
    drawGoal(0, 210, false); drawGoal(1000, 210, true);
  }

  function drawFaceoff(x, y) {
    ctx.strokeStyle = "rgba(213, 39, 69, .35)"; ctx.lineWidth = 3; ctx.beginPath(); ctx.arc(x, y, 44, 0, Math.PI * 2); ctx.stroke();
    ctx.fillStyle = "rgba(213, 39, 69, .45)"; ctx.beginPath(); ctx.arc(x, y, 4, 0, Math.PI * 2); ctx.fill();
  }

  function drawGoal(x, y, right) {
    ctx.save(); ctx.strokeStyle = "#e33a50"; ctx.fillStyle = "rgba(255,255,255,.22)"; ctx.lineWidth = 6;
    const start = right ? x - 1 : x - 54; ctx.beginPath(); ctx.rect(start, y, 55, 180); ctx.fill(); ctx.stroke();
    ctx.globalAlpha = .26; ctx.lineWidth = 1;
    for (let yy = y + 12; yy < y + 180; yy += 12) { ctx.beginPath(); ctx.moveTo(start, yy); ctx.lineTo(start + 55, yy); ctx.stroke(); }
    ctx.restore();
  }

  function drawPlayer(player) {
    const color = player.team === "blue" ? "#119eef" : "#ef3659";
    ctx.save(); ctx.translate(player.x, player.y);
    if (player.id === playerId) { ctx.strokeStyle = "#b9f227"; ctx.lineWidth = 4; ctx.beginPath(); ctx.arc(0, 0, 33, 0, Math.PI * 2); ctx.stroke(); }
    ctx.shadowColor = color; ctx.shadowBlur = 17; ctx.fillStyle = color; ctx.beginPath(); ctx.arc(0, 0, 26, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0; ctx.fillStyle = "rgba(255,255,255,.22)"; ctx.beginPath(); ctx.arc(-7, -8, 9, 0, Math.PI * 2); ctx.fill();
    ctx.fillStyle = "white"; ctx.font = "900 15px system-ui"; ctx.textAlign = "center"; ctx.textBaseline = "middle"; ctx.fillText(player.number, 0, 1);
    if (!player.connected) { ctx.fillStyle = "rgba(6,15,21,.62)"; ctx.beginPath(); ctx.arc(0,0,26,0,Math.PI*2); ctx.fill(); }
    ctx.restore();
  }

  function drawPuck(puck) {
    ctx.save(); ctx.translate(puck.x, puck.y); ctx.shadowColor = "rgba(0,0,0,.6)"; ctx.shadowBlur = 10; ctx.shadowOffsetY = 5;
    ctx.fillStyle = "#111b20"; ctx.beginPath(); ctx.ellipse(0, 0, 16, 14, 0, 0, Math.PI * 2); ctx.fill();
    ctx.shadowBlur = 0; ctx.fillStyle = "#37454b"; ctx.beginPath(); ctx.ellipse(-3, -4, 6, 3, -.2, 0, Math.PI * 2); ctx.fill(); ctx.restore();
  }

  connect();
  draw();
})();
