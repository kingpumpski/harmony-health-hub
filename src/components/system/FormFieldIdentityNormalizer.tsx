import { useLayoutEffect } from "react";

const FIELD_SELECTOR = "input, select, textarea";
const IDENTITY_FIELD_SELECTOR = "input, select, textarea, button[type=\"submit\"]";

function nextAvailableId(prefix: string, start: number) {
  let index = start;
  while (document.getElementById(`${prefix}-${index}`)) index += 1;
  return { id: `${prefix}-${index}`, next: index + 1 };
}

function fieldKey(field: HTMLElement) {
  return [
    field.getAttribute("autocomplete"),
    field.getAttribute("name"),
    field.getAttribute("id"),
    field.getAttribute("placeholder"),
    field.getAttribute("type"),
  ]
    .filter(Boolean)
    .join(" ")
    .toLowerCase();
}

function inferAutocomplete(field: HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement) {
  if (field.hasAttribute("autocomplete")) return;

  const key = fieldKey(field);
  const type = field instanceof HTMLInputElement ? field.type.toLowerCase() : "";

  let value = "off";
  if (type === "email" || /(^|[-_ ])email/.test(key)) value = "email";
  else if (type === "tel" || /phone|mobile|telephone/.test(key)) value = "tel";
  else if (type === "password") value = /confirm|repeat|verify/.test(key) ? "new-password" : "current-password";
  else if (/first[-_ ]?name|given[-_ ]?name/.test(key)) value = "given-name";
  else if (/last[-_ ]?name|family[-_ ]?name|surname/.test(key)) value = "family-name";
  else if (/username|user[-_ ]?name/.test(key)) value = "username";
  else if (/street|address[-_ ]?line|postal|zip|city|state|region|country/.test(key)) value = "street-address";
  else if (/organization|company|employer/.test(key)) value = "organization";
  else if (/search/.test(key) || type === "search") value = "off";

  field.setAttribute("autocomplete", value);
}

function readableFieldName(field: HTMLElement) {
  const raw = field.getAttribute("aria-label")
    || field.getAttribute("placeholder")
    || field.getAttribute("name")
    || field.getAttribute("id")
    || field.getAttribute("type")
    || "form field";
  return raw
    .replace(/[-_]+/g, " ")
    .replace(/([a-z])([A-Z])/g, "$1 $2")
    .replace(/^./, (char) => char.toUpperCase());
}

function associateLabels() {
  document.querySelectorAll<HTMLLabelElement>("label").forEach((label) => {
    if (label.htmlFor) return;

    const nested = label.querySelector<HTMLElement>(FIELD_SELECTOR);
    if (nested) {
      if (!nested.id) {
        const candidate = nextAvailableId("harmony-label-field", 1);
        nested.id = candidate.id;
      }
      label.htmlFor = nested.id;
      return;
    }

    const parent = label.parentElement;
    if (!parent) return;
    const siblings = Array.from(parent.querySelectorAll<HTMLElement>(FIELD_SELECTOR))
      .filter((field) => !field.closest("label"));
    if (siblings.length === 1) {
      const [field] = siblings;
      if (!field.id) {
        const candidate = nextAvailableId("harmony-label-field", 1);
        field.id = candidate.id;
      }
      label.htmlFor = field.id;
    }
  });
}

function normalizeFormFields() {
  const forms = Array.from(document.forms);
  let formIndex = 1;
  let standaloneFieldIndex = 1;

  forms.forEach((form) => {
    if (!form.id) {
      const candidate = nextAvailableId("harmony-form", formIndex);
      form.id = candidate.id;
      formIndex = candidate.next;
    }

    Array.from(form.querySelectorAll<HTMLElement>(IDENTITY_FIELD_SELECTOR)).forEach((field) => {
      if (!field.id && !field.getAttribute("name")) {
        const candidate = nextAvailableId(`${form.id}-field`, 1);
        field.id = candidate.id;
      }
    });
  });

  Array.from(document.querySelectorAll<HTMLElement>(IDENTITY_FIELD_SELECTOR)).forEach((field) => {
    if (field.closest("form")) return;
    if (!field.id && !field.getAttribute("name")) {
      const candidate = nextAvailableId("harmony-field", standaloneFieldIndex);
      field.id = candidate.id;
      standaloneFieldIndex = candidate.next;
    }
  });

  associateLabels();

  document.querySelectorAll<HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement>(FIELD_SELECTOR).forEach((field) => {
    inferAutocomplete(field);

    const hasExplicitName = field.getAttribute("aria-label") || field.getAttribute("aria-labelledby");
    const associatedLabel = field.id
      ? document.querySelector<HTMLLabelElement>(`label[for="${CSS.escape(field.id)}"]`)
      : null;
    const wrappingLabel = field.closest("label");

    if (!hasExplicitName && !associatedLabel && !wrappingLabel) {
      field.setAttribute("aria-label", readableFieldName(field));
    }
  });
}

export function FormFieldIdentityNormalizer() {
  useLayoutEffect(() => {
    normalizeFormFields();

    const observer = new MutationObserver(() => normalizeFormFields());
    observer.observe(document.body, { childList: true, subtree: true });

    return () => observer.disconnect();
  }, []);

  return null;
}
