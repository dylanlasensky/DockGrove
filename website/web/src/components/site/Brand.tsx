import Link from "next/link";
import Image from "next/image";

type BrandProps = {
  /** Where the wordmark links to. The home header/footer use `#top`; other pages use `/`. */
  href?: string;
  /** Extra classes on the link (e.g. home nav sizing). */
  className?: string;
  /** Extra classes on the wordmark image (e.g. `max-[700px]:w-[138px] max-[700px]:h-[33px]`). */
  imageClassName?: string;
  "aria-label"?: string;
};

/**
 * `<a class="brand"><img class="brand-wordmark" ...></a>` from the original pages:
 * the owner-provided wordmark on a white rounded tile.
 */
export default function Brand({
  href = "/",
  className = "",
  imageClassName = "",
  "aria-label": ariaLabel,
}: BrandProps) {
  return (
    <Link
      href={href}
      aria-label={ariaLabel}
      className={`inline-flex items-center gap-[10px] text-[1.375rem] font-[650] tracking-[-1px] no-underline ${className}`}
    >
      <Image
        src="/assets/DockGrove-wordmark.png"
        width={168}
        height={40}
        alt="DockGrove"
        priority
        className={`h-10 w-[168px] shrink-0 rounded-[5px] bg-white object-contain p-[3px] ${imageClassName}`}
      />
    </Link>
  );
}
