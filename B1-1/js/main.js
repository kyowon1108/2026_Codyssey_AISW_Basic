const root = document.documentElement;
const header = document.querySelector("#site-header");
const navigation = document.querySelector("#site-nav");
const menuToggle = document.querySelector("#menu-toggle");
const themeToggle = document.querySelector("#theme-toggle");
const backToTop = document.querySelector("#back-to-top");
const projectsStatus = document.querySelector("#projects-status");
const projectsGrid = document.querySelector("#projects-grid");
const contactForm = document.querySelector("#contact-form");
const formResult = document.querySelector("#form-result");

const state = {
  theme: "light",
  projects: { status: "loading", items: [] },
  form: { submitted: false },
};

const getSavedTheme = () => {
  try {
    return localStorage.getItem("theme") === "dark" ? "dark" : "light";
  } catch {
    return "light";
  }
};

const saveTheme = (theme) => {
  try {
    localStorage.setItem("theme", theme);
  } catch {
    // The visible theme still works when storage is unavailable.
  }
};

const renderTheme = () => {
  root.dataset.theme = state.theme;
  const isDark = state.theme === "dark";
  themeToggle.setAttribute("aria-pressed", String(isDark));
  themeToggle.setAttribute("aria-label", isDark ? "라이트 모드 켜기" : "다크 모드 켜기");
  document.querySelector('meta[name="theme-color"]').content = isDark ? "#101820" : "#ffffff";
};

state.theme = getSavedTheme();
renderTheme();

themeToggle.addEventListener("click", () => {
  state.theme = state.theme === "light" ? "dark" : "light";
  saveTheme(state.theme);
  renderTheme();
});

const setMenuOpen = (open) => {
  navigation.classList.toggle("active", open);
  if (open) {
    header.classList.add("menu-open");
  } else {
    header.classList.remove("menu-open");
  }
  menuToggle.setAttribute("aria-expanded", String(open));
  menuToggle.setAttribute("aria-label", open ? "메뉴 닫기" : "메뉴 열기");
};

menuToggle.addEventListener("click", () => {
  setMenuOpen(!navigation.classList.contains("active"));
});

document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && navigation.classList.contains("active")) {
    setMenuOpen(false);
    menuToggle.focus();
  }
});

document.querySelectorAll('a[href^="#"]').forEach((link) => {
  link.addEventListener("click", (event) => {
    const target = document.querySelector(link.getAttribute("href"));
    if (!target) return;
    event.preventDefault();
    target.scrollIntoView({ behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
    if (link.classList.contains("skip-link")) target.focus({ preventScroll: true });
    history.replaceState(null, "", link.getAttribute("href"));
    setMenuOpen(false);
  });
});

const updateScrollControls = () => {
  header.classList.toggle("scrolled", window.scrollY >= 60);
  const showBackToTop = window.scrollY >= 300;
  backToTop.classList.toggle("visible", showBackToTop);
  backToTop.tabIndex = showBackToTop ? 0 : -1;
  backToTop.setAttribute("aria-hidden", String(!showBackToTop));
};

window.addEventListener("scroll", updateScrollControls, { passive: true });
window.addEventListener("resize", () => {
  if (window.innerWidth >= 768) setMenuOpen(false);
});
updateScrollControls();

backToTop.addEventListener("click", () => {
  document.querySelector(".wordmark").focus({ preventScroll: true });
  window.scrollTo({ top: 0, behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "instant" : "smooth" });
});

const revealSections = () => {
  const sections = document.querySelectorAll(".reveal");
  if (!("IntersectionObserver" in window) || matchMedia("(prefers-reduced-motion: reduce)").matches) {
    sections.forEach((section) => section.classList.add("visible"));
    return;
  }

  root.classList.add("js-enabled");
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      if (!entry.isIntersecting) return;
      entry.target.classList.add("visible");
      observer.unobserve(entry.target);
    });
  }, { threshold: 0.2 });
  sections.forEach((section) => observer.observe(section));
};

revealSections();

const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
})[character]);

const renderProjectCard = (repo) => {
  const { name, description, language, stargazers_count: stars } = repo;
  const summaries = {
    "kw-notice-mcp": "학교 공지를 읽기 전용 MCP 데이터로 제공하는 도구",
    "activities-mcp": "대외활동 정보를 수집해 검색 가능한 MCP 데이터로 제공하는 도구",
    "furniture-platform": "실시간 협업으로 3D 공간에 가구를 배치하는 플랫폼",
    "gsplat-onthefly-nvs-study": "3D Gaussian Splatting 기반 새 시점 합성 연구",
    "afterglow-computer-graphics-final": "Three.js로 만든 빛 퍼즐 게임",
  };
  const safeName = escapeHtml(name);
  const safeDescription = escapeHtml(summaries[name] || description || "설명이 등록되지 않은 공개 저장소입니다.");
  const safeLanguage = escapeHtml(language || "기타");
  const url = `https://github.com/kyowon1108/${encodeURIComponent(name)}`;
  return `
    <article class="project-card">
      <div class="project-card-head">
        <h3><a href="${url}" target="_blank" rel="noopener noreferrer">${safeName}</a></h3>
        <span class="project-card-arrow" aria-hidden="true">↗</span>
      </div>
      <p>${safeDescription}</p>
      <div class="project-meta"><span class="project-language">${safeLanguage}</span><span aria-label="별 ${stars}개">★ ${stars}</span></div>
    </article>`;
};

const renderProjects = () => {
  const { status, items } = state.projects;
  projectsStatus.classList.toggle("sr-only", status === "success");
  projectsGrid.innerHTML = status === "success" ? items.map(renderProjectCard).join("") : "";

  if (status === "loading") {
    projectsStatus.textContent = "프로젝트를 불러오는 중입니다...";
  } else if (status === "empty") {
    projectsStatus.textContent = "표시할 프로젝트가 없습니다.";
  } else if (status === "success") {
    projectsStatus.textContent = `프로젝트 ${items.length}개를 불러왔습니다.`;
  } else if (status === "error") {
    projectsStatus.innerHTML = '<p>프로젝트를 불러올 수 없습니다.</p><button class="button button-secondary retry-button" type="button">다시 시도</button>';
    projectsStatus.querySelector("button").addEventListener("click", loadProjects);
  }
};

async function loadProjects() {
  state.projects = { status: "loading", items: [] };
  renderProjects();

  try {
    const response = await fetch("https://api.github.com/users/kyowon1108/repos?per_page=100&sort=updated", {
      headers: { Accept: "application/vnd.github+json" },
    });
    if (!response.ok) throw new Error(`GitHub API: ${response.status}`);
    const data = await response.json();
    if (!Array.isArray(data)) throw new Error("GitHub API returned an unexpected response");

    const featuredNames = ["kw-notice-mcp", "activities-mcp", "furniture-platform", "gsplat-onthefly-nvs-study", "afterglow-computer-graphics-final"];
    const available = data.filter((repo) => !repo.archived && !repo.private && repo.name !== "kyowon1108" && !repo.name.startsWith("2026_Codyssey"));
    const featured = featuredNames.map((name) => available.find((repo) => repo.name === name)).filter(Boolean);
    const recent = available
      .filter((repo) => !featuredNames.includes(repo.name) && !repo.fork)
      .sort((a, b) => new Date(b.pushed_at) - new Date(a.pushed_at));
    const items = featured.length ? featured : recent.slice(0, 6);
    state.projects = { status: items.length ? "success" : "empty", items };
  } catch (error) {
    console.error("GitHub projects could not be loaded:", error);
    state.projects = { status: "error", items: [] };
  }

  renderProjects();
}

loadProjects();

const fields = {
  name: document.querySelector("#contact-name"),
  email: document.querySelector("#contact-email"),
  message: document.querySelector("#contact-message"),
};

const validateField = (name) => {
  const value = fields[name].value.trim();
  if (!value) return "필수 항목을 입력해 주세요.";
  if (name === "email" && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value)) return "올바른 이메일 주소를 입력해 주세요.";
  return "";
};

const renderField = (name) => {
  const error = validateField(name);
  fields[name].setAttribute("aria-invalid", String(Boolean(error)));
  document.querySelector(`#${name}-error`).textContent = error;
  return !error;
};

Object.entries(fields).forEach(([name, field]) => {
  field.addEventListener("input", () => {
    if (state.form.submitted || field.getAttribute("aria-invalid") === "true") renderField(name);
    formResult.textContent = "";
  });
});

contactForm.addEventListener("submit", (event) => {
  event.preventDefault();
  state.form.submitted = true;
  const results = Object.keys(fields).map(renderField);
  if (results.every(Boolean)) {
    formResult.textContent = "입력 확인 완료. 이 데모에서는 메시지가 실제로 전송되지 않습니다.";
  } else {
    formResult.textContent = "입력 내용을 확인해 주세요.";
    Object.values(fields).find((field) => field.getAttribute("aria-invalid") === "true").focus();
  }
});

document.querySelector("#footer-year").textContent = new Date().getFullYear();
