const escapeHtml = (value: unknown) => String(value ?? '').replace(/[&<>"']/g, (c) => ({ '&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;', "'":'&#39;' }[c] ?? c));

export function renderTemplate(template: string, variables: Record<string, unknown>): string {
  return template.replace(/{{\s*([A-Za-z0-9_.-]+)\s*}}/g, (_match, key: string) => {
    const value = key.split('.').reduce<unknown>((acc, part) => (acc as Record<string, unknown> | null)?.[part], variables);
    return escapeHtml(value);
  });
}

export function renderPlainText(template: string, variables: Record<string, unknown>): string {
  return renderTemplate(template, variables).replace(/<[^>]*>/g, '').replace(/\s+/g, ' ').trim();
}