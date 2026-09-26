import { useLayoutEffect } from "react";

const FIELD_SELECTOR = "input, select, textarea, button[type=\"submit\"]";

function nextAvailableId(prefix: string, start: number) {
  let index = start;
  while (document.getElementById(`${prefix}-${index}`)) index += 1;
  return { id: `${prefix}-${index}`, next: index + 1 };
}

function normalizeFormFieldIds() {
  const forms = Array.from(document.forms);
  let formIndex = 1;
  let standaloneFieldIndex = 1;

  forms.forEach((form) => {
    if (!form.id) {
      const candidate = nextAvailableId("harmony-form", formIndex);
      form.id = candidate.id;
      formIndex = candidate.next;
    }

    const fields = Array.from(form.querySelectorAll<HTMLElement>(FIELD_SELECTOR));
    fields.forEach((field) => {
      if (field.id || field.getAttribute("name")) return;
      const candidate = nextAvailableId(`${form.id}-field`, 1);
      field.id = candidate.id;
    });
  });

  Array.from(document.querySelectorAll<HTMLElement>(FIELD_SELECTOR)).forEach((field) => {
    if (field.closest("form")) return;
    if (field.id || field.getAttribute("name")) return;

    const candidate = nextAvailableId("harmony-field", standaloneFieldIndex);
    field.id = candidate.id;
    standaloneFieldIndex = candidate.next;
  });
}

export function FormFieldIdentityNormalizer() {
  useLayoutEffect(() => {
    normalizeFormFieldIds();

    const observer = new MutationObserver(() => normalizeFormFieldIds());
    observer.observe(document.body, { childList: true, subtree: true });

    return () => observer.disconnect();
  }, []);

  return null;
}
