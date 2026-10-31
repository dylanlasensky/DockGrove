"use client";

import { useState } from "react";
import {
  DOWNLOAD_FILENAME,
  downloadApp,
  errorMessage,
} from "@/lib/commerce";
import { button, fine, h2, licenseOutput, p } from "./classes";

/** The `#license-section` block shared by purchase and recovery: copy + download. */
export default function LicensePanel({ license }: { license: string }) {
  const [copyStatus, setCopyStatus] = useState("");
  const [downloading, setDownloading] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(license);
      setCopyStatus("License copied.");
    } catch {
      setCopyStatus("Select and copy the license above.");
    }
  }

  async function download() {
    setDownloading(true);
    setCopyStatus("Preparing your download…");
    try {
      const blob = await downloadApp(license);
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = DOWNLOAD_FILENAME;
      a.click();
      setTimeout(() => URL.revokeObjectURL(url), 1000);
      setCopyStatus(
        "Download started. Save your license before leaving this page.",
      );
    } catch (error) {
      setCopyStatus(errorMessage(error));
    } finally {
      setDownloading(false);
    }
  }

  return (
    <section id="license-section">
      <h2 className={h2}>Your license</h2>
      <p className={p}>
        Keep this license somewhere safe. In DockGrove, open Settings → License,
        paste it, and choose Activate. Never post it in a public support issue.
      </p>
      <div id="license-output" className={licenseOutput}>
        {license}
      </div>
      <button
        type="button"
        className={`${button} mt-3`}
        id="copy-license"
        onClick={copy}
      >
        Copy license
      </button>{" "}
      <button
        type="button"
        className={`${button} mt-3`}
        id="download-app"
        onClick={download}
        disabled={downloading}
      >
        Download DockGrove
      </button>
      <p id="copy-status" className={fine} role="status">
        {copyStatus}
      </p>
      <p className={fine}>
        Test licenses work with the configured test build. This candidate has
        not been Apple-notarized. A download is available only after the
        release artifact has been configured.
      </p>
    </section>
  );
}
