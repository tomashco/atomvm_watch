export interface ConsolePane { out(line: string): void; err(line: string): void; clear(): void }

export function makeConsole(el: HTMLElement): ConsolePane {
  const add = (line: string, cls: string) => {
    const d = document.createElement("div"); d.className = cls; d.textContent = line;
    el.appendChild(d); el.scrollTop = el.scrollHeight;
  };
  return { out: (l) => add(l, "out"), err: (l) => add(l, "err"), clear: () => { el.textContent = ""; } };
}
