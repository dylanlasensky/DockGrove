"use client";

import { useEffect, useState, useSyncExternalStore, type FormEvent } from "react";
import {
  assertLicense,
  completeRecovery,
  errorMessage,
  RECOVERY_DEFAULT_MESSAGE,
  RECOVERY_REQUESTED_MESSAGE,
  RECOVERY_RESTORED_MESSAGE,
  RECOVERY_VERIFYING_MESSAGE,
  recoveryToken,
  requestRecovery,
} from "@/lib/commerce";
import LicensePanel from "./LicensePanel";
import { cardButton, formCard, full, input, label, statusMessage } from "./classes";

// The one-time token arrives in the URL fragment. It is read once per page load and
// the fragment is scrubbed from history (effect below) so it never lingers or gets shared.
let consumedToken: string | null | undefined;
const noSubscribe = () => () => {};
const getToken = () => {
  if (consumedToken === undefined) consumedToken = recoveryToken(window.location.hash);
  return consumedToken;
};
const getServerToken = () => null;

/** Port of the recover.html `.form-card` and app.js recovery behavior. */
export default function RecoveryFlow() {
  const token = useSyncExternalStore(noSubscribe, getToken, getServerToken);
  const [status, setStatus] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [license, setLicense] = useState("");

  useEffect(() => {
    if (window.location.hash)
      history.replaceState(null, "", window.location.pathname + window.location.search);
    if (!token) return;
    let cancelled = false;
    completeRecovery(token)
      .then((result) => {
        if (cancelled) return;
        setLicense(assertLicense(result.licenseKey));
        setStatus(RECOVERY_RESTORED_MESSAGE);
      })
      .catch((error) => {
        if (!cancelled) setStatus(errorMessage(error));
      });
    return () => {
      cancelled = true;
    };
  }, [token]);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const email = new FormData(event.currentTarget).get("email");
    setBusy(true);
    setStatus("Requesting recovery…");
    try {
      await requestRecovery(typeof email === "string" ? email : "");
      setStatus(RECOVERY_REQUESTED_MESSAGE);
    } catch (error) {
      setStatus(errorMessage(error));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className={formCard}>
      <form id="recovery-form" method="post" action="/api/recover" onSubmit={onSubmit}>
        <label className={label} htmlFor="recovery-email">
          Purchase email
        </label>
        <input
          className={input}
          id="recovery-email"
          name="email"
          type="email"
          autoComplete="email"
          required
          maxLength={254}
          placeholder="you@example.com"
        />
        <button
          className={`${cardButton} ${full}`}
          id="recover-button"
          type="submit"
          disabled={busy}
        >
          Send recovery instructions
        </button>
      </form>
      <p id="recovery-status" className={statusMessage} role="status">
        {status ?? (token ? RECOVERY_VERIFYING_MESSAGE : RECOVERY_DEFAULT_MESSAGE)}
      </p>
      {license && <LicensePanel license={license} />}
    </div>
  );
}
