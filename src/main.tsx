import { createRoot } from "react-dom/client";
import App from "./App.tsx";
import "./index.css";
import { FormFieldIdentityNormalizer } from "./components/system/FormFieldIdentityNormalizer";

if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    const serviceWorkerUrl = `${import.meta.env.BASE_URL}sw.js`;
    navigator.serviceWorker.register(serviceWorkerUrl, { updateViaCache: 'none' })
      .then((registration) => registration.update())
      .catch((error) => {
        console.warn('Harmony Health Hub service worker registration failed', error);
      });
  });
}

createRoot(document.getElementById("root")!).render(\n  <>\n    <FormFieldIdentityNormalizer />\n    <App />\n  </>\n);
