import { useLayoutEffect } from "react";

const FIELD_SELECTOR = "input, select, textarea, button[type=\"submit\"]";

function normalizeFormFieldIds() {
  const forms = Array.from(document.forms);
  let standaloneFieldIndex = 0;

  forms.forEach((form, formIndex) => {
    if (!form.id) form.id = `harmony-form-${formIndex + 1}`;

    const fields = Array.from(form.querySelectorAll<HTMLElement>(FIELD_SELECTOR));
    fields.forEach((field, fieldIndex) => {
      if (field.id || field.getAttribute("name")) return;
      field.id = `${form.id}-field-${fieldIndex + 1}`;
    });
  });

  Array.from(document.querySelectorAll<HTMLElement>(FIELD_SELECTOR)).forEach((field) => {
    if (field.closest("form")) return;
    if (field.id || field.getAttribute("name")) return;
    standaloneFieldIndex += 1;
    field.id = `harmony-field-${standaloneFieldIndex}`;
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
