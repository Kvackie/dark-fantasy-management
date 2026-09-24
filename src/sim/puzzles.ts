/**
 * The forge puzzles a craft is decided by.
 *
 * Each is a small state machine with no renderer: `step` moves it on by a
 * number of seconds, the named actions are the player's buttons, and the forge
 * scene only draws what it reads back. That keeps the timing rules testable and
 * the scene free of game logic.
 *
 * All four end the same way — a success, or five misses — and the number of
 * misses is what sets the quality of the piece.
 */

export const MAX_FAILURES = 5;

export type PuzzleKind = 'timing_strike' | 'heat_balance' | 'bellows_rhythm' | 'edge_sharpening';
export const PUZZLE_KINDS: readonly PuzzleKind[] = [
  'timing_strike',
  'heat_balance',
  'bellows_rhythm',
  'edge_sharpening',
];

/** A source of numbers in [0, 1). Puzzles use it only for where things start. */
export type Random = () => number;

export interface PuzzleProgress {
  /** i18n key of the progress line. */
  key: string;
  params: Record<string, string | number>;
}

export abstract class ForgePuzzle {
  abstract readonly kind: PuzzleKind;
  started = false;
  completed = false;
  success = false;
  failures = 0;
  /** i18n key of the line under the title. */
  feedback: string;

  constructor(feedback: string) {
    this.feedback = feedback;
  }

  start(): void {
    if (this.started || this.completed) return;
    this.started = true;
    this.onStart();
  }

  /** Advance by `dt` seconds. */
  step(dt: number): void {
    if (!this.started || this.completed || dt <= 0) return;
    this.onStep(Math.min(dt, 0.25));
  }

  protected onStart(): void {}
  protected abstract onStep(dt: number): void;
  abstract progress(): PuzzleProgress;

  protected finish(success: boolean): void {
    this.completed = true;
    this.success = success;
    this.feedback = success ? `puzzle.${this.kind}.done` : 'puzzle.failed';
  }

  /** Count a miss; five of them end the puzzle. Returns true if that ended it. */
  protected miss(feedback: string): boolean {
    this.failures += 1;
    this.feedback = feedback;
    if (this.failures >= MAX_FAILURES) {
      this.finish(false);
      return true;
    }
    return false;
  }
}

/**
 * Timing Strike: a marker sweeps a bar; strike while it overlaps the red heart
 * of the hot zone. Three clean strikes win.
 */
export class TimingStrike extends ForgePuzzle {
  readonly kind = 'timing_strike';
  static readonly BAR = 620;
  static readonly TARGET = 92;
  static readonly MARKER = 26;
  static readonly REQUIRED = 3;
  static readonly SPEED = 0.92;
  static readonly PAUSE = 0.45;
  static readonly RED_START = 0.25;
  static readonly RED_END = 0.75;

  strikes = 0;
  /** Left edge of the hot zone, in bar units. */
  targetX = 0;
  /** Marker position along the bar, 0–1. */
  markerT = 0;
  direction = 1;
  /** Seconds left of the pause after a strike. */
  pause = 0;

  constructor(private random: Random = Math.random) {
    super('puzzle.timing_strike.ready');
    this.resetRound();
  }

  private resetRound(): void {
    this.targetX = this.random() * (TimingStrike.BAR - TimingStrike.TARGET);
    this.markerT = this.random();
    this.direction = this.random() >= 0.5 ? 1 : -1;
  }

  redZone(): [number, number] {
    return [
      this.targetX + TimingStrike.TARGET * TimingStrike.RED_START,
      this.targetX + TimingStrike.TARGET * TimingStrike.RED_END,
    ];
  }

  protected override onStep(dt: number): void {
    if (this.pause > 0) {
      this.pause -= dt;
      if (this.pause <= 0) {
        this.pause = 0;
        this.resetRound();
      }
      return;
    }
    this.markerT += dt * TimingStrike.SPEED * this.direction;
    if (this.markerT >= 1) {
      this.markerT = 1;
      this.direction = -1;
    } else if (this.markerT <= 0) {
      this.markerT = 0;
      this.direction = 1;
    }
  }

  /** Is a strike possible right now, rather than waiting out the pause? */
  get ready(): boolean {
    return this.started && !this.completed && this.pause <= 0;
  }

  strike(): void {
    if (!this.ready) return;
    const left = this.markerT * TimingStrike.BAR - TimingStrike.MARKER / 2;
    const right = left + TimingStrike.MARKER;
    const [redStart, redEnd] = this.redZone();
    const overlap = Math.min(right, redEnd) - Math.max(left, redStart);
    this.pause = TimingStrike.PAUSE;
    if (overlap >= TimingStrike.MARKER * 0.5) {
      this.strikes += 1;
      this.feedback = 'puzzle.timing_strike.hit';
      if (this.strikes >= TimingStrike.REQUIRED) this.finish(true);
    } else {
      this.miss('puzzle.timing_strike.miss');
    }
  }

  override progress(): PuzzleProgress {
    return {
      key: 'puzzle.timing_strike.progress',
      params: {
        done: this.strikes,
        need: TimingStrike.REQUIRED,
        miss: this.failures,
        max: MAX_FAILURES,
      },
    };
  }
}

/** Shared by the two puzzles that are about holding a value inside a band for a while. */
abstract class HoldPuzzle extends ForgePuzzle {
  held = 0;
  outside = 0;

  protected abstract readonly required: number;
  protected abstract readonly grace: number;
  protected abstract inBand(): boolean;
  protected abstract drift(dt: number): void;
  protected abstract readonly holdingKey: string;
  protected abstract readonly slippingKey: string;

  protected override onStart(): void {
    this.feedback = this.holdingKey;
  }

  protected override onStep(dt: number): void {
    this.drift(dt);
    if (this.inBand()) {
      this.held += dt;
      this.outside = 0;
      this.feedback = this.holdingKey;
      if (this.held >= this.required) this.finish(true);
      return;
    }
    this.outside += dt;
    this.feedback = this.slippingKey;
    if (this.outside >= this.grace) {
      this.outside = 0;
      this.miss(this.slippingKey);
    }
  }

  override progress(): PuzzleProgress {
    return {
      key: `puzzle.${this.kind}.progress`,
      params: {
        held: this.held.toFixed(1),
        need: this.required.toFixed(1),
        miss: this.failures,
        max: MAX_FAILURES,
      },
    };
  }
}

/** Heat Balance: the forge cools on its own; keep it in the safe centre band for four seconds. */
export class HeatBalance extends HoldPuzzle {
  readonly kind = 'heat_balance';
  static readonly SAFE_MIN = 0.42;
  static readonly SAFE_MAX = 0.58;
  static readonly STEP = 0.09;
  protected readonly required = 4;
  protected readonly grace = 0.8;
  protected readonly holdingKey = 'puzzle.heat_balance.hold';
  protected readonly slippingKey = 'puzzle.heat_balance.drift';

  heat = 0.5;

  constructor() {
    super('puzzle.heat_balance.ready');
  }

  protected override inBand(): boolean {
    return this.heat >= HeatBalance.SAFE_MIN && this.heat <= HeatBalance.SAFE_MAX;
  }

  protected override drift(dt: number): void {
    this.heat = Math.max(0, Math.min(1, this.heat - 0.07 * dt));
  }

  stoke(): void {
    this.adjust(HeatBalance.STEP);
  }

  vent(): void {
    this.adjust(-HeatBalance.STEP);
  }

  private adjust(delta: number): void {
    if (!this.started || this.completed) return;
    this.heat = Math.max(0, Math.min(1, this.heat + delta));
  }
}

/**
 * Edge Sharpening: the angle drifts away from centre and speeds up as it goes.
 * Nudge it back and hold it on the edge for four seconds.
 */
export class EdgeSharpening extends HoldPuzzle {
  readonly kind = 'edge_sharpening';
  static readonly EDGE = 0.13;
  static readonly NUDGE = 0.09;
  protected readonly required = 4;
  protected readonly grace = 0.75;
  protected readonly holdingKey = 'puzzle.edge_sharpening.hold';
  protected readonly slippingKey = 'puzzle.edge_sharpening.drift';

  /** −1 to 1; zero is a perfect edge. */
  position = 0;
  velocity = 0.12;

  constructor() {
    super('puzzle.edge_sharpening.ready');
  }

  protected override inBand(): boolean {
    return Math.abs(this.position) <= EdgeSharpening.EDGE;
  }

  protected override drift(dt: number): void {
    this.velocity += Math.sign(this.position) * 0.28 * dt;
    // Damping was per frame at 60 fps; scaled here so it holds at any frame rate.
    this.velocity *= 0.985 ** (dt * 60);
    this.position = Math.max(-1, Math.min(1, this.position + this.velocity * dt));
  }

  nudge(direction: -1 | 1): void {
    if (!this.started || this.completed) return;
    const amount = EdgeSharpening.NUDGE * direction;
    this.position = Math.max(-1, Math.min(1, this.position + amount));
    this.velocity = Math.max(-0.45, Math.min(0.45, this.velocity + amount * 1.2));
  }
}

/** Bellows Rhythm: pump while the beat marker is in the red window. Five good pumps win. */
export class BellowsRhythm extends ForgePuzzle {
  readonly kind = 'bellows_rhythm';
  static readonly BEAT = 1.15;
  static readonly WINDOW = 0.12;
  static readonly REQUIRED = 5;

  pumps = 0;
  /** Where in the beat the marker is, 0–1; the window is centred on 0.5. */
  phase = 0;
  private wasInWindow = false;
  private hitThisBeat = false;

  constructor() {
    super('puzzle.bellows_rhythm.ready');
  }

  inWindow(): boolean {
    return Math.abs(this.phase - 0.5) <= BellowsRhythm.WINDOW;
  }

  protected override onStep(dt: number): void {
    this.phase = (this.phase + dt / BellowsRhythm.BEAT) % 1;
    const inWindow = this.inWindow();
    if (inWindow && !this.wasInWindow) this.hitThisBeat = false;
    const missedBeat = !inWindow && this.wasInWindow && !this.hitThisBeat;
    this.wasInWindow = inWindow;
    if (missedBeat) this.miss('puzzle.bellows_rhythm.missed');
  }

  pump(): void {
    if (!this.started || this.completed) return;
    if (this.inWindow()) {
      this.hitThisBeat = true;
      this.pumps += 1;
      this.feedback = 'puzzle.bellows_rhythm.hit';
      if (this.pumps >= BellowsRhythm.REQUIRED) this.finish(true);
    } else {
      this.miss('puzzle.bellows_rhythm.off');
    }
  }

  override progress(): PuzzleProgress {
    return {
      key: 'puzzle.bellows_rhythm.progress',
      params: {
        done: this.pumps,
        need: BellowsRhythm.REQUIRED,
        miss: this.failures,
        max: MAX_FAILURES,
      },
    };
  }
}

export function createPuzzle(kind: PuzzleKind, random: Random = Math.random): ForgePuzzle {
  switch (kind) {
    case 'timing_strike':
      return new TimingStrike(random);
    case 'heat_balance':
      return new HeatBalance();
    case 'bellows_rhythm':
      return new BellowsRhythm();
    case 'edge_sharpening':
      return new EdgeSharpening();
  }
}

export function randomPuzzleKind(random: Random = Math.random): PuzzleKind {
  return PUZZLE_KINDS[Math.floor(random() * PUZZLE_KINDS.length)] ?? 'timing_strike';
}
