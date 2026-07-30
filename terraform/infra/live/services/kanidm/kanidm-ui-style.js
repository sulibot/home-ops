// Load Kanidm's versioned theme script through the proxy, then add a small
// guard for its server-rendered login form. Without this guard, a double click
// can submit the one-time password form twice: the first request succeeds and
// consumes auth-session-id, while the second replaces the redirect with
// InvalidAuthState.
(() => {
  const currentScript = document.currentScript;
  const query = currentScript && currentScript.src.includes("?")
    ? currentScript.src.slice(currentScript.src.indexOf("?"))
    : "";
  const upstreamStyle = document.createElement("script");
  upstreamStyle.src = "/pkg/style-upstream.js" + query;
  upstreamStyle.async = false;
  document.head.appendChild(upstreamStyle);

  document.addEventListener("submit", (event) => {
    const form = event.target;
    if (!(form instanceof HTMLFormElement) || form.id !== "login") {
      return;
    }
    if (form.dataset.kanidmSubmitting === "true") {
      event.preventDefault();
      event.stopImmediatePropagation();
      return;
    }
    form.dataset.kanidmSubmitting = "true";
    form.querySelectorAll("button[type='submit'], input[type='submit']")
      .forEach((control) => {
        control.disabled = true;
        control.setAttribute("aria-busy", "true");
      });
  }, true);
})();
