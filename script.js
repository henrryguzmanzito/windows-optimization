(() => {
  "use strict";

  const canvas = document.getElementById("board");
  const ctx = canvas.getContext("2d");

  const scoreEl = document.getElementById("score");
  const bestEl = document.getElementById("best");
  const overlay = document.getElementById("overlay");
  const overlayTitle = document.getElementById("overlayTitle");
  const overlayText = document.getElementById("overlayText");
  const startBtn = document.getElementById("startBtn");
  const pauseBtn = document.getElementById("pauseBtn");
  const restartBtn = document.getElementById("restartBtn");

  const GRID = 20; // 20 x 20 cells
  const CELL = canvas.width / GRID; // pixels per cell
  const BEST_KEY = "snake_best_score";

  const START_SPEED = 160; // ms per step
  const MIN_SPEED = 70;
  const SPEED_STEP = 4; // speed up per food eaten

  let snake, dir, nextDir, food, score, best, speed;
  let loopId = null;
  let running = false;
  let paused = false;

  best = Number(localStorage.getItem(BEST_KEY) || 0);
  bestEl.textContent = best;

  function reset() {
    snake = [
      { x: 8, y: 10 },
      { x: 7, y: 10 },
      { x: 6, y: 10 },
    ];
    dir = { x: 1, y: 0 };
    nextDir = { x: 1, y: 0 };
    score = 0;
    speed = START_SPEED;
    scoreEl.textContent = score;
    placeFood();
    draw();
  }

  function placeFood() {
    let spot;
    do {
      spot = {
        x: Math.floor(Math.random() * GRID),
        y: Math.floor(Math.random() * GRID),
      };
    } while (snake.some((s) => s.x === spot.x && s.y === spot.y));
    food = spot;
  }

  function step() {
    dir = nextDir;
    const head = { x: snake[0].x + dir.x, y: snake[0].y + dir.y };

    // Wall collision
    if (head.x < 0 || head.y < 0 || head.x >= GRID || head.y >= GRID) {
      return gameOver();
    }
    // Self collision
    if (snake.some((s) => s.x === head.x && s.y === head.y)) {
      return gameOver();
    }

    snake.unshift(head);

    if (head.x === food.x && head.y === food.y) {
      score += 10;
      scoreEl.textContent = score;
      if (score > best) {
        best = score;
        bestEl.textContent = best;
        localStorage.setItem(BEST_KEY, String(best));
      }
      speed = Math.max(MIN_SPEED, speed - SPEED_STEP);
      placeFood();
      restartLoop();
    } else {
      snake.pop();
    }

    draw();
  }

  function draw() {
    ctx.clearRect(0, 0, canvas.width, canvas.height);

    // Food
    drawCell(food.x, food.y, "#f43f5e", true);

    // Snake
    snake.forEach((s, i) => {
      const shade = i === 0 ? "#4ade80" : "#22c55e";
      drawCell(s.x, s.y, shade);
    });
  }

  function drawCell(cx, cy, color, isFood = false) {
    const pad = 2;
    const x = cx * CELL + pad;
    const y = cy * CELL + pad;
    const size = CELL - pad * 2;
    ctx.fillStyle = color;
    const r = isFood ? size / 2 : 5;
    roundRect(x, y, size, size, r);
    ctx.fill();
  }

  function roundRect(x, y, w, h, r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }

  function restartLoop() {
    if (loopId) clearInterval(loopId);
    loopId = setInterval(step, speed);
  }

  function start() {
    if (running) return;
    reset();
    running = true;
    paused = false;
    overlay.classList.add("hidden");
    pauseBtn.disabled = false;
    pauseBtn.textContent = "Pausa";
    restartLoop();
  }

  function togglePause() {
    if (!running) return;
    paused = !paused;
    if (paused) {
      clearInterval(loopId);
      loopId = null;
      pauseBtn.textContent = "Reanudar";
      showOverlay("Pausa", "Pulsa reanudar o Espacio para continuar.", "Reanudar");
    } else {
      overlay.classList.add("hidden");
      pauseBtn.textContent = "Pausa";
      restartLoop();
    }
  }

  function gameOver() {
    running = false;
    paused = false;
    if (loopId) clearInterval(loopId);
    loopId = null;
    pauseBtn.disabled = true;
    pauseBtn.textContent = "Pausa";
    showOverlay(
      "¡Game Over!",
      `Puntuación: ${score} · Récord: ${best}`,
      "Jugar de nuevo"
    );
  }

  function showOverlay(title, text, btnLabel) {
    overlayTitle.textContent = title;
    overlayText.textContent = text;
    startBtn.textContent = btnLabel;
    overlay.classList.remove("hidden");
  }

  function setDirection(name) {
    const map = {
      up: { x: 0, y: -1 },
      down: { x: 0, y: 1 },
      left: { x: -1, y: 0 },
      right: { x: 1, y: 0 },
    };
    const nd = map[name];
    if (!nd) return;
    // Prevent reversing directly onto itself
    if (nd.x === -dir.x && nd.y === -dir.y) return;
    nextDir = nd;
  }

  // Keyboard controls
  window.addEventListener("keydown", (e) => {
    const key = e.key.toLowerCase();
    if (["arrowup", "arrowdown", "arrowleft", "arrowright", " "].includes(key)) {
      e.preventDefault();
    }
    if (key === "arrowup" || key === "w") setDirection("up");
    else if (key === "arrowdown" || key === "s") setDirection("down");
    else if (key === "arrowleft" || key === "a") setDirection("left");
    else if (key === "arrowright" || key === "d") setDirection("right");
    else if (key === " " || key === "p") {
      if (running) togglePause();
      else start();
    }
  });

  // On-screen dpad
  document.querySelectorAll(".dpad__btn").forEach((btn) => {
    btn.addEventListener("click", () => setDirection(btn.dataset.dir));
  });

  // Touch swipe controls on the board
  let touchStart = null;
  canvas.addEventListener(
    "touchstart",
    (e) => {
      const t = e.changedTouches[0];
      touchStart = { x: t.clientX, y: t.clientY };
    },
    { passive: true }
  );
  canvas.addEventListener(
    "touchend",
    (e) => {
      if (!touchStart) return;
      const t = e.changedTouches[0];
      const dx = t.clientX - touchStart.x;
      const dy = t.clientY - touchStart.y;
      if (Math.abs(dx) < 20 && Math.abs(dy) < 20) return;
      if (Math.abs(dx) > Math.abs(dy)) {
        setDirection(dx > 0 ? "right" : "left");
      } else {
        setDirection(dy > 0 ? "down" : "up");
      }
      touchStart = null;
    },
    { passive: true }
  );

  startBtn.addEventListener("click", () => {
    if (paused) togglePause();
    else start();
  });
  pauseBtn.addEventListener("click", togglePause);
  restartBtn.addEventListener("click", () => {
    running = false;
    if (loopId) clearInterval(loopId);
    loopId = null;
    start();
  });

  // Initial render
  reset();
})();
