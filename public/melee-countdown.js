// Playback follows Elm's displayed server deadline. No timers or network messages.
class UqmCountdown extends HTMLElement {
  static observedAttributes = ["data-seconds", "data-muted"];
  connectedCallback() {
    this.clips = Array.from({length: 6}, (_, n) => {
      const audio = new Audio(`/sounds/countdown/${n || "tick"}.wav`);
      audio.preload = "auto";
      audio.volume = n ? .55 : .10;
      return audio;
    });
    this.previous = Number(this.dataset.seconds);
    this.visibility = () => { this.stop(); this.previous = Number(this.dataset.seconds); };
    document.addEventListener("visibilitychange", this.visibility);
  }
  attributeChangedCallback() {
    // Elm may update seconds and mute together; handle the completed DOM patch.
    queueMicrotask(() => {
      if (!this.isConnected || !this.clips) return;
      const seconds = Number(this.dataset.seconds), previous = this.previous;
      this.previous = seconds;
      if (this.dataset.muted === "true" || document.hidden) { this.stop(); return; }
      // Never replay missed seconds after a suspended tab, reload, or clock jump.
      if (!Number.isInteger(seconds) || seconds <= 0 || previous - seconds !== 1) return;
      this.stop();
      const clip = this.clips[seconds <= 5 ? seconds : 0];
      clip.currentTime = 0;
      clip.play().catch(() => {});
    });
  }
  stop() { this.clips?.forEach(clip => clip.pause()); }
  disconnectedCallback() {
    this.stop();
    document.removeEventListener("visibilitychange", this.visibility);
  }
}
if (!customElements.get("uqm-countdown")) customElements.define("uqm-countdown", UqmCountdown);
