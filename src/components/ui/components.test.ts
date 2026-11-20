import { createElement } from "react";
import { renderToStaticMarkup } from "react-dom/server";
import { describe, expect, it } from "vitest";
import { Button, Card, Choice, ConfirmAction, DateTime, EmptyState, Field, FieldGrid, Money, MoneyInput, Notice, Page, PageHeader, StatusBadge, Table, Td, Th } from "./index";

const html = (el: Parameters<typeof renderToStaticMarkup>[0]) => renderToStaticMarkup(el);

describe("Button", () => {
  it("keeps type, disabled and variant class", () => {
    const out = html(createElement(Button, { type: "submit", disabled: true, variant: "primary" }, "Save"));
    expect(out).toContain('type="submit"');
    expect(out).toContain('disabled=""');
    expect(out).toContain("ui-button--primary");
  });
  it("loading disables, sets aria-busy and keeps the label", () => {
    const out = html(createElement(Button, { type: "button", loading: true }, "Saving"));
    expect(out).toContain('disabled=""');
    expect(out).toContain('aria-busy="true"');
    expect(out).toContain("Saving");
  });
});

describe("Field", () => {
  const input = (props: Record<string, unknown> = {}) => createElement("input", { name: "email", ...props });
  const id = (out: string) => /<input[^>]*\sid="([^"]+)"/.exec(out)![1];

  it("ties the label to the control and keeps its name", () => {
    const out = html(createElement(Field, { label: "Email" }, input()));
    expect(out).toContain('name="email"');
    expect(out).toContain(`for="${id(out)}"`);
    expect(out).toMatch(/<label[^>]*>Email<\/label>/);
  });
  it("renders hint and error outside the label and describes the control with them", () => {
    const out = html(createElement(Field, { label: "Email", hint: "H", error: "E" }, input()));
    expect(out).toMatch(/<label[^>]*>Email<\/label>/);
    expect(out).toContain('aria-invalid="true"');
    const i = id(out);
    expect(out).toContain(`aria-describedby="${i}-hint ${i}-error"`);
    expect(out).toContain(`id="${i}-hint"`);
    expect(out).toContain(`id="${i}-error"`);
  });
  it("no error means no aria-invalid", () => {
    expect(html(createElement(Field, { label: "L", hint: "H" }, input()))).not.toContain("aria-invalid");
  });
  it("keeps the child's own id and aria-describedby", () => {
    const out = html(createElement(Field, { label: "L", error: "E" }, input({ id: "mine", "aria-describedby": "other" })));
    expect(out).toContain('for="mine"');
    expect(out).toContain('aria-describedby="other mine-error"');
  });
  it("uses the id prop when the child has none", () => {
    const out = html(createElement(Field, { label: "L", id: "given" }, input()));
    expect(out).toContain('for="given"');
    expect(out).toMatch(/<input[^>]*id="given"/);
  });
  it("renders nothing for false or empty hint and error", () => {
    const out = html(createElement(Field, { label: "L", hint: "", error: "" }, input()));
    expect(out).not.toContain("ui-field-hint");
    expect(out).not.toContain("ui-field-error");
    expect(out).not.toContain("aria-describedby");
  });
});

describe("root attribute forwarding", () => {
  const cases: [string, () => ReturnType<typeof createElement>][] = [
    ["Button", () => createElement(Button, { type: "button", "data-testid": "t" })],
    ["Card", () => createElement(Card, { "data-testid": "t" })],
    ["Field", () => createElement(Field, { label: "L", "data-testid": "t" } as never, createElement("input"))],
    ["FieldGrid", () => createElement(FieldGrid, { "data-testid": "t" } as never)],
    ["Choice", () => createElement(Choice, { label: "L", "data-testid": "t" } as never)],
    ["MoneyInput", () => createElement(MoneyInput, { "data-testid": "t" } as never)],
    ["Notice", () => createElement(Notice, { tone: "info", "data-testid": "t" })],
    ["StatusBadge", () => createElement(StatusBadge, { status: { kind: "bidding", status: "Open" }, "data-testid": "t" })],
    ["Money", () => createElement(Money, { cents: 1, "data-testid": "t" } as never)],
    ["DateTime", () => createElement(DateTime, { iso: "2026-01-01T00:00:00Z", tz: "UTC", "data-testid": "t" } as never)],
    ["Table", () => createElement(Table, { "data-testid": "t" })],
    ["Th", () => createElement("table", null, createElement("thead", null, createElement("tr", null, createElement(Th, { "data-testid": "t" } as never))))],
    ["Td", () => createElement("table", null, createElement("tbody", null, createElement("tr", null, createElement(Td, { "data-testid": "t" } as never))))],
    ["EmptyState", () => createElement(EmptyState, { "data-testid": "t" } as never)],
    ["PageHeader", () => createElement(PageHeader, { title: "T", "data-testid": "t" } as never)],
    ["Page", () => createElement(Page, { "data-testid": "t" } as never)],
  ];
  for (const [name, make] of cases) {
    it(`${name} forwards data-testid`, () => {
      expect(html(make())).toContain('data-testid="t"');
    });
  }
  it("forwards id and aria-* too", () => {
    expect(html(createElement(Card, { id: "x", "aria-label": "y" } as never))).toMatch(/id="x"[^>]*aria-label="y"/);
  });
});

describe("Table", () => {
  it("puts data-testid on the table inside the scroll wrapper", () => {
    const out = html(createElement(Table, { "data-testid": "tabulation" }));
    expect(out).toContain("ui-table-scroll");
    expect(out).toMatch(/<table[^>]*data-testid="tabulation"/);
  });
  it("numeric cells are right-aligned tabular", () => {
    const out = html(
      createElement("table", null,
        createElement("tbody", null,
          createElement("tr", null, createElement(Td, { numeric: true }, "1")))),
    );
    expect(out).toContain("ui-num");
    expect(out).toContain("tabular");
  });
});

describe("Notice", () => {
  it("renders no role by default and keeps data-testid", () => {
    const out = html(createElement(Notice, { tone: "warning", "data-testid": "sealed" }, "x"));
    expect(out).toContain('data-testid="sealed"');
    expect(out).not.toContain("role=");
  });
  it("renders a given role", () => {
    expect(html(createElement(Notice, { tone: "error", role: "alert" }, "x"))).toContain('role="alert"');
  });
});

describe("StatusBadge", () => {
  it("non-responsive is a danger alert badge", () => {
    const out = html(createElement(StatusBadge, { status: { kind: "original", received: false }, role: "alert" }));
    expect(out).toContain("ui-badge--danger");
    expect(out).toContain('role="alert"');
    expect(out).toContain("Non-responsive");
  });
  it("label overrides text but not tone", () => {
    const out = html(createElement(StatusBadge, { status: { kind: "bidding", status: "Open" }, label: "Bidding open" }));
    expect(out).toContain("ui-badge--success");
    expect(out).toContain("Bidding open");
  });
});

describe("Money", () => {
  it("formats cents with tabular numerals", () => {
    const out = html(createElement(Money, { cents: 12_734_567 }));
    expect(out).toContain("$127,345.67");
    expect(out).toContain("tabular");
  });
});

describe("ConfirmAction", () => {
  it("starts as a plain button (type=button) that does not submit, with no confirm step", () => {
    const out = html(createElement(ConfirmAction, {
      label: "Post award", confirmLabel: "Confirm: post award publicly", warning: "Cannot be undone.",
      describedBy: "why", "data-testid": "post",
    }));
    expect(out).toContain('type="button"');
    expect(out).not.toContain('type="submit"');
    expect(out).toContain('aria-describedby="why"');
    expect(out).toContain("Post award");
    expect(out).not.toContain("Confirm: post award publicly");
    expect(out).not.toContain("Cannot be undone.");
  });
  it("disabled keeps the disabled look on the first button", () => {
    const out = html(createElement(ConfirmAction, {
      label: "Post award", confirmLabel: "Confirm", warning: "W", disabled: true,
    }));
    expect(out).toContain('disabled=""');
  });
});
