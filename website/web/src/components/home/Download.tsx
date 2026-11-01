"use client";

import { useReveal } from "@/hooks/useReveal";
import { useProduct } from "@/lib/home/useProduct";
import {
  buttonClass,
  emClass,
  eyebrowClass,
  fineClass,
  h2Class,
  pClass,
  sectionClass,
  textLinkBaseClass,
} from "@/lib/home/classes";

/** The marketing CTA never starts checkout (`data-coming-soon="true"` in the original). */
const COMING_SOON = true;

/** `.download :focus-visible{outline-color:#b4cef3}` */
const downloadFocusClass =
  "focus-visible:outline-3 focus-visible:outline-[#b4cef3] focus-visible:outline-offset-[5px]";

export default function Download() {
  const section = useReveal<HTMLElement>();
  const product = useProduct(COMING_SOON);

  return (
    <section
      ref={section}
      id="download"
      className={`reveal ${sectionClass} bg-[#171a1c] text-center text-[#f5f6f3]`}
    >
      {/* eslint-disable-next-line @next/next/no-img-element -- static export, exact original markup */}
      <img
        src="/assets/DockGrove-icon.png"
        alt=""
        width={84}
        height={84}
        className="mb-[30px] inline-block max-[700px]:h-[68px] max-[700px]:w-[68px]"
      />
      <p className={eyebrowClass}>DOCKGROVE FOR MAC</p>
      <h2 className={`${h2Class} text-[clamp(55px,8vw,105px)]`}>
        A little more
        <br />
        <em className={`${emClass} text-[#b2c2b3]`}>in your flow.</em>
      </h2>
      <p className={`${pClass} my-[25px] text-[#8f9a92]`}>
        One purchase. Your everyday, a little closer.
      </p>
      <div className="mx-auto mt-[35px] mb-6 flex items-center justify-center gap-[22px] max-[700px]:flex-col max-[700px]:gap-2.5">
        <strong data-price className="text-[3rem] leading-[normal] font-medium tracking-[-.05em]">
          {product.price}
        </strong>
        <span className="text-left text-[.8125rem] leading-[1.7] text-[#b8c2b9] max-[700px]:text-center">
          Planned one-time price · USD
          <br />
          Version 1 + maintenance updates · <span data-devices>{product.devices}</span>{" "}
          personal Macs
        </span>
      </div>
      <button
        type="button"
        id="checkout-button"
        data-coming-soon="true"
        disabled={product.buttonDisabled}
        onClick={product.checkout}
        className={`${buttonClass} ${downloadFocusClass} mb-5 bg-[#eef1e9] text-[#1b231e] hover:bg-[#d6e3d4] max-[700px]:gap-5 max-[700px]:text-[.8125rem]`}
      >
        {product.buttonLabel}
      </button>
      <p
        id="checkout-status"
        className={`${fineClass} text-[#b8c2b9] max-[700px]:text-[.6875rem]`}
        role="status"
      >
        {product.status}
      </p>
      <p className={`${pClass} my-[25px] text-xs text-[#929c95]`}>
        Not yet Apple-notarized. Signing and customer terms are being finalized.
      </p>
      <div className="mt-5 flex justify-center gap-6">
        <a
          className={`${textLinkBaseClass} ${downloadFocusClass} text-[.8125rem] text-[#c1ccc3]`}
          href="/terms"
        >
          Proposed terms ↗
        </a>
        <a
          className={`${textLinkBaseClass} ${downloadFocusClass} text-[.8125rem] text-[#c1ccc3]`}
          href="/recover"
        >
          Restore purchase ↗
        </a>
      </div>
    </section>
  );
}
