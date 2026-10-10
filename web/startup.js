// Keep startup logic in a same-origin file so Hosting can reject inline scripts.
if (navigator.language.startsWith('en')) {
  document.documentElement.lang = 'en';
  document.getElementById('loading-message').textContent = 'Preparing your workspace.';
}
window.addEventListener('flutter-first-frame', () => {
  document.getElementById('loading')?.remove();
});
