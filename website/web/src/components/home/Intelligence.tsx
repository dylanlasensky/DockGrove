"use client";

import Image from "next/image";
import { useRef, useState } from "react";
import { useReveal } from "@/hooks/useReveal";

type ProviderKey = "claude" | "codex" | "gemini" | "api";

const PROVIDERS: Record<
  ProviderKey,
  { name: string; value: string; suffix: string; unit: string; bar: number; detail: string; description: string }
> = {
  claude: {
    name: "Claude Code",
    value: "76",
    suffix: "%",
    unit: "5-hour allowance remaining",
    bar: 76,
    detail: "Weekly and session windows, read locally from Claude Code’s supported status line.",
    description:
      "Connect the local status line for supported Claude Pro and Max allowance windows. No browser cookies or account password needed.",
  },
  codex: {
    name: "Codex",
    value: "82",
    suffix: "%",
    unit: "Reported allowance remaining",
    bar: 82,
    detail: "The account windows and reset times supplied by your signed-in Codex app.",
    description:
      "Use your existing Codex sign-in to read its reported allowances and reset windows. Ordinary ChatGPT message counts are not included.",
  },
  gemini: {
    name: "Gemini CLI",
    value: "12.4",
    suffix: "k",
    unit: "Tokens in the imported session",
    bar: 45,
    detail: "A local session report. Input, output, cached tokens, and requests by model.",
    description:
      "Import a Gemini CLI JSON report, or pipe one through DockGrove’s local capture command. This measures session activity, not remaining Gemini chat quota.",
  },
  api: {
    name: "API & teams",
    value: "148",
    suffix: "k",
    unit: "Input tokens · illustrative API report",
    bar: 62,
    detail: "OpenAI and Claude organization usage, plus Cursor team activity.",
    description:
      "Connect provider admin credentials for organization API tokens or Cursor team activity. Keys stay in macOS Keychain and requests go directly to that provider.",
  },
};

const ORDER: ProviderKey[] = ["claude", "codex", "gemini", "api"];

export default function Intelligence() {
  const heading = useReveal<HTMLDivElement>();
  const showcase = useReveal<HTMLDivElement>();
  const [current, setCurrent] = useState<ProviderKey>("claude");
  const tabRefs = useRef<(HTMLButtonElement | null)[]>([]);
  const data = PROVIDERS[current];

  const select = (index: number) => {
    setCurrent(ORDER[index]);
    tabRefs.current[index]?.focus();
  };

  const onKeyDown = (event: React.KeyboardEvent, index: number) => {
    let next: number | undefined;
    if (event.key === "ArrowRight") next = (index + 1) % ORDER.length;
    if (event.key === "ArrowLeft") next = (index - 1 + ORDER.length) % ORDER.length;
    if (event.key === "Home") next = 0;
    if (event.key === "End") next = ORDER.length - 1;
    if (next !== undefined) {
      event.preventDefault();
      select(next);
    }
  };

  return (
    <section
      id="intelligence"
      className="relative scroll-mt-[100px] overflow-hidden bg-[#111214] p-[125px_max(6vw,24px)] text-center leading-[normal] text-[#f4f5f6] [overflow-wrap:anywhere] [&_:focus-visible]:outline-[#b4cef3] max-[700px]:p-[80px_24px]"
    >
      <div ref={heading} className="reveal mx-auto max-w-[750px]">
        <p className="m-0 mb-[26px] text-[0.6875rem] font-[650] leading-[1.55] tracking-[.15em]">A CLEARER VIEW OF AI</p>
        <h2 className="m-0 text-[clamp(45px,6.1vw,84px)] font-semibold leading-[1.04] tracking-[-.065em]">
          Stay in the flow.
          <br />
          <span className="text-[#727980]">Know what’s left.</span>
        </h2>
        <p className="m-0 mx-auto mt-[25px] max-w-[510px] text-[1.125rem] leading-[1.55] text-[#92979e] max-[700px]:text-[1rem]">
          Bring your AI tools into view, with honest labels for allowances, session activity, and API usage.
        </p>
      </div>
      <div
        ref={showcase}
        className="reveal mx-auto flex max-w-[1000px] items-center justify-center gap-[100px] py-[60px] max-[1000px]:gap-[60px] max-[700px]:gap-0 max-[700px]:p-[45px_0_35px]"
      >
        <div
          className="relative grid h-[250px] w-[250px] place-items-center rounded-full border border-[#a7b8a92c] shadow-[0_0_0_28px_#a7b8a905,0_0_0_58px_#a7b8a904,0_0_100px_#82ad9410] after:absolute after:inset-[-32px] after:rounded-full after:border after:border-[#9fafb61d] after:content-[''] after:[transform:rotateX(58deg)_rotate(-20deg)] max-[700px]:hidden"
          aria-hidden="true"
        >
          <Image
            src="/assets/DockGrove-icon.png"
            width={100}
            height={100}
            alt=""
            className="rounded-[26px] shadow-[0_14px_40px_#0008]"
            unoptimized
          />
        </div>
        <div className="min-h-[270px] w-[340px] rounded-[24px] border border-[#ffffff21] bg-[linear-gradient(140deg,#34383c,#1b1d20)] p-[26px_30px] text-left shadow-[0_25px_50px_#0005] max-[700px]:w-[min(340px,100%)]">
          <div className="flex items-center justify-between text-[0.8125rem]">
            <span id="provider-name">{data.name}</span>
            <span className="rounded-[4px] border border-[#ffffff20] p-[4px_5px] text-[.6875rem] tracking-[.15em] text-[#9ca6a2]">SAMPLE</span>
          </div>
          <strong className="mt-[26px] block text-[4.6875rem] font-medium leading-[1.1] tracking-[-5px] tabular-nums" id="provider-value">
            {data.value}
            <span className="text-[1.5625rem] tracking-[-1px]">{data.suffix}</span>
          </strong>
          <span className="text-[0.6875rem] text-[#b6bec2]" id="provider-unit">
            {data.unit}
          </span>
          <div className="my-[19px] h-[4px] overflow-hidden rounded-[10px] bg-[#ffffff15]">
            <i
              className="block h-full rounded-[10px] bg-[#c0d7c7] transition-[width] duration-600 ease-[var(--ease)]"
              id="provider-bar"
              style={{ width: `${data.bar}%` }}
            />
          </div>
          <p className="m-0 text-[0.6875rem] leading-[1.5] text-[#abb3bb]" id="provider-detail">
            {data.detail}
          </p>
        </div>
      </div>
      <div
        className="inline-flex gap-[4px] rounded-[35px] border border-[#ffffff0a] bg-[#ffffff07] p-[5px] max-[700px]:mx-auto max-[700px]:grid max-[700px]:max-w-[350px] max-[700px]:grid-cols-2 max-[700px]:rounded-[20px]"
        role="tablist"
        aria-label="AI integration preview"
      >
        {ORDER.map((key, index) => {
          const selected = key === current;
          return (
            <button
              key={key}
              ref={(element) => {
                tabRefs.current[index] = element;
              }}
              type="button"
              role="tab"
              aria-selected={selected}
              aria-controls="provider-description"
              tabIndex={selected ? 0 : -1}
              data-provider={key}
              onClick={() => setCurrent(key)}
              onKeyDown={(event) => onKeyDown(event, index)}
              className={`min-h-[44px] min-w-[44px] cursor-pointer rounded-[24px] border-0 p-[13px_22px] text-[0.75rem] transition-[background,color] duration-250 active:brightness-[.92] max-[700px]:p-[12px_18px] max-[700px]:text-[0.6875rem] ${
                selected ? "bg-[#e2e7e3] text-[#171c1a]" : "bg-transparent text-[#959da4]"
              }`}
            >
              {PROVIDERS[key].name}
            </button>
          );
        })}
      </div>
      <p
        id="provider-description"
        className="mx-auto mt-[25px] min-h-[55px] max-w-[590px] text-[0.875rem] leading-[1.55] text-[#b4babf] max-[700px]:min-h-[75px] max-[700px]:text-[0.8125rem]"
        role="tabpanel"
        tabIndex={0}
      >
        {data.description}
      </p>
      <p className="m-0 mx-auto mt-[18px] max-w-[650px] text-[0.75rem] leading-[1.65] text-[#abb3bb] max-[700px]:text-[0.6875rem]">
        Provider availability varies. Gemini session tokens are not a remaining subscription quota. API reports require the provider’s credentials.
      </p>
    </section>
  );
}
