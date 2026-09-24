/**
 * Sound, synthesised with the Web Audio API.
 *
 * No files: every effect is a few oscillators and a noise burst shaped by an
 * envelope, and the ambience is a low detuned drone with a slow filter sweep.
 * That keeps the download small and sidesteps licensing entirely.
 *
 * Browsers only allow audio to start from a user gesture, so the context is
 * created on the first press anywhere on the page. Music and effects each have
 * their own bus under the master, so the Settings page can level them apart.
 */

import type { LogKind } from '@/sim/types';
import { onSettingsChange, settings, updateSettings, type Settings } from '@/ui/settings';

const MASTER_LEVEL = 0.6;

let context: AudioContext | null = null;
let master: GainNode | null = null;
let musicBus: GainNode | null = null;
let effectsBus: GainNode | null = null;
let ambience: { stop: () => void } | null = null;

export function isMuted(): boolean {
  return !settings().sound;
}

export function setMuted(value: boolean): void {
  updateSettings({ sound: !value });
}

/** Follow the settings: levels glide rather than jump, and the drone starts once it is wanted. */
function applyLevels(current: Readonly<Settings>): void {
  if (!context || !master || !musicBus || !effectsBus) return;
  const now = context.currentTime;
  master.gain.setTargetAtTime(current.sound ? MASTER_LEVEL : 0, now, 0.05);
  musicBus.gain.setTargetAtTime(current.music / 100, now, 0.05);
  effectsBus.gain.setTargetAtTime(current.effects / 100, now, 0.05);
  startAmbience();
}

onSettingsChange(applyLevels);

/** Create the audio graph on the first user gesture. Safe to call repeatedly. */
export function unlockAudio(): void {
  if (context) {
    if (context.state === 'suspended') void context.resume();
    return;
  }
  const Ctor =
    window.AudioContext ??
    (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctor) return;
  try {
    context = new Ctor();
  } catch {
    return;
  }
  master = context.createGain();
  master.gain.value = settings().sound ? MASTER_LEVEL : 0;
  master.connect(context.destination);
  musicBus = context.createGain();
  musicBus.gain.value = settings().music / 100;
  musicBus.connect(master);
  effectsBus = context.createGain();
  effectsBus.gain.value = settings().effects / 100;
  effectsBus.connect(master);
  startAmbience();
}

function startAmbience(): void {
  const wanted = settings().sound && settings().music > 0;
  if (!context || !musicBus || ambience || !wanted) return;
  const ctx = context;
  const gain = ctx.createGain();
  gain.gain.value = 0;
  gain.gain.linearRampToValueAtTime(0.05, ctx.currentTime + 4);
  const filter = ctx.createBiquadFilter();
  filter.type = 'lowpass';
  filter.frequency.value = 320;
  filter.Q.value = 4;
  const lfo = ctx.createOscillator();
  const lfoGain = ctx.createGain();
  lfo.frequency.value = 0.05;
  lfoGain.gain.value = 180;
  lfo.connect(lfoGain).connect(filter.frequency);
  const voices = [55, 55.4, 82.4, 110.2].map((frequency, i) => {
    const osc = ctx.createOscillator();
    osc.type = i % 2 ? 'sawtooth' : 'triangle';
    osc.frequency.value = frequency;
    osc.connect(filter);
    osc.start();
    return osc;
  });
  filter.connect(gain).connect(musicBus);
  lfo.start();
  ambience = {
    stop: () => {
      voices.forEach((osc) => osc.stop());
      lfo.stop();
    },
  };
}

type Effect = 'hit' | 'miss' | 'click' | 'victory' | 'defeat' | 'alarm' | 'chime' | 'forge';

function tone(
  frequency: number,
  start: number,
  duration: number,
  type: OscillatorType,
  volume: number,
  slideTo?: number,
): void {
  if (!context || !effectsBus) return;
  const osc = context.createOscillator();
  const gain = context.createGain();
  osc.type = type;
  osc.frequency.setValueAtTime(frequency, start);
  if (slideTo) osc.frequency.exponentialRampToValueAtTime(slideTo, start + duration);
  gain.gain.setValueAtTime(0.0001, start);
  gain.gain.exponentialRampToValueAtTime(volume, start + 0.01);
  gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
  osc.connect(gain).connect(effectsBus);
  osc.start(start);
  osc.stop(start + duration + 0.05);
}

function noise(start: number, duration: number, volume: number, cutoff: number): void {
  if (!context || !effectsBus) return;
  const length = Math.floor(context.sampleRate * duration);
  const buffer = context.createBuffer(1, length, context.sampleRate);
  const data = buffer.getChannelData(0);
  for (let i = 0; i < length; i += 1) data[i] = (Math.random() * 2 - 1) * (1 - i / length);
  const source = context.createBufferSource();
  source.buffer = buffer;
  const filter = context.createBiquadFilter();
  filter.type = 'bandpass';
  filter.frequency.value = cutoff;
  const gain = context.createGain();
  gain.gain.value = volume;
  source.connect(filter).connect(gain).connect(effectsBus);
  source.start(start);
}

export function play(effect: Effect): void {
  if (!context || !settings().sound || settings().effects === 0) return;
  const now = context.currentTime;
  switch (effect) {
    case 'click':
      tone(660, now, 0.05, 'triangle', 0.05);
      break;
    case 'hit':
      noise(now, 0.18, 0.5, 2400);
      tone(980, now, 0.35, 'triangle', 0.18, 700);
      break;
    case 'forge':
      noise(now, 0.25, 0.35, 900);
      break;
    case 'miss':
      tone(220, now, 0.25, 'sawtooth', 0.08, 140);
      break;
    case 'victory':
      [392, 494, 587, 784].forEach((f, i) => tone(f, now + i * 0.11, 0.5, 'triangle', 0.12));
      break;
    case 'defeat':
      [330, 262, 196].forEach((f, i) => tone(f, now + i * 0.18, 0.6, 'sawtooth', 0.07));
      break;
    case 'alarm':
      tone(140, now, 0.8, 'sawtooth', 0.09, 90);
      noise(now, 0.5, 0.15, 300);
      break;
    case 'chime':
      [659, 988].forEach((f, i) => tone(f, now + i * 0.09, 0.6, 'sine', 0.1));
      break;
  }
}

/** The sound that goes with a log entry, if any. */
export function playFor(kind: LogKind): void {
  if (kind === 'victory') play('victory');
  else if (kind === 'defeat') play('defeat');
  else if (kind === 'broken' || kind === 'wounded') play('alarm');
  else if (kind === 'restored' || kind === 'healed' || kind === 'level') play('chime');
}
