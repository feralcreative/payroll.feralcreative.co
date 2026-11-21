// Feral / Tame, the client portal's switch. Loaded in <head> so a saved Tame
// choice applies before first paint. Feral is the default.
(function payrollTheme() {
  const key = 'feral:payroll-theme';
  const root = document.documentElement;
  const apply = (theme) => {
    if (theme === 'tame') root.dataset.theme = 'tame';
    else delete root.dataset.theme;
    for (const button of document.querySelectorAll('[data-theme-choice]')) {
      button.setAttribute('aria-pressed', String(button.dataset.themeChoice === theme));
    }
  };
  let saved = 'feral';
  try {
    saved = localStorage.getItem(key) === 'tame' ? 'tame' : 'feral';
  } catch {
    // Storage may be unavailable; Feral it is.
  }
  apply(saved);
  document.addEventListener('DOMContentLoaded', () => {
    apply(saved);
    for (const button of document.querySelectorAll('[data-theme-choice]')) {
      button.addEventListener('click', () => {
        if (button.dataset.themeChoice === saved) return;
        saved = button.dataset.themeChoice;
        // Crossfade where View Transitions exist; otherwise, or with reduced motion, switch at once.
        if (document.startViewTransition && matchMedia('(prefers-reduced-motion: no-preference)').matches) document.startViewTransition(() => apply(saved));
        else apply(saved);
        try {
          localStorage.setItem(key, saved);
        } catch {
          // The switch still works for this visit.
        }
      });
    }
  });
})();
