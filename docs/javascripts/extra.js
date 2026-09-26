// Reading progress bar with MkDocs Material instant navigation support
function setupReadingProgress() {
  let progressBar = document.getElementById("reading-progress-bar");
  if (!progressBar) {
    progressBar = document.createElement("div");
    progressBar.id = "reading-progress-bar";
    document.body.appendChild(progressBar);
  }

  const updateProgress = () => {
    const scrollTotal = document.documentElement.scrollHeight - window.innerHeight;
    if (scrollTotal <= 0) {
      progressBar.style.width = "0%";
      return;
    }
    const currentScroll = window.scrollY;
    const progress = Math.min(100, Math.max(0, (currentScroll / scrollTotal) * 100));
    progressBar.style.width = `${progress}%`;
  };

  window.removeEventListener("scroll", updateProgress);
  window.addEventListener("scroll", updateProgress, { passive: true });
  updateProgress();
}

function initInteractiveFeatures() {
  setupReadingProgress();
}

if (typeof document$ !== "undefined") {
  document$.subscribe(() => {
    initInteractiveFeatures();
  });
} else {
  document.addEventListener("DOMContentLoaded", () => {
    initInteractiveFeatures();
  });
}
