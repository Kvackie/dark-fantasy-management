import { describe, expect, it } from 'vitest';
import {
  BellowsRhythm,
  EdgeSharpening,
  HeatBalance,
  MAX_FAILURES,
  TimingStrike,
} from '@/sim/puzzles';

/** Run a puzzle forward in small steps, as the frame loop would. */
function run(puzzle: { step(dt: number): void }, seconds: number, dt = 1 / 60): void {
  for (let t = 0; t < seconds; t += dt) puzzle.step(dt);
}

describe('timing strike', () => {
  it('counts a strike on the red zone as a hit and one far from it as a miss', () => {
    const puzzle = new TimingStrike(() => 0.5);
    puzzle.start();
    const [start, end] = puzzle.redZone();
    puzzle.markerT = (start + end) / 2 / TimingStrike.BAR;
    puzzle.strike();
    expect(puzzle.strikes).toBe(1);
    expect(puzzle.ready).toBe(false); // paused after a strike
    run(puzzle, TimingStrike.PAUSE + 0.05);
    expect(puzzle.ready).toBe(true);

    puzzle.markerT = puzzle.targetX > TimingStrike.BAR / 2 ? 0 : 1;
    puzzle.strike();
    expect(puzzle.failures).toBe(1);
  });

  it('wins on three hits and loses on five misses', () => {
    const win = new TimingStrike(() => 0.3);
    win.start();
    for (let i = 0; i < 3; i += 1) {
      const [start, end] = win.redZone();
      win.markerT = (start + end) / 2 / TimingStrike.BAR;
      win.strike();
      run(win, 0.5);
    }
    expect(win.completed && win.success).toBe(true);

    const lose = new TimingStrike(() => 0.9);
    lose.start();
    for (let i = 0; i < MAX_FAILURES; i += 1) {
      lose.markerT = 0;
      lose.strike();
      run(lose, 0.5);
    }
    expect(lose.completed).toBe(true);
    expect(lose.success).toBe(false);
  });
});

describe('heat balance', () => {
  it('fails slowly if left alone, and succeeds if held in the band', () => {
    const idle = new HeatBalance();
    idle.start();
    run(idle, 20);
    expect(idle.completed).toBe(true);
    expect(idle.success).toBe(false);

    const tended = new HeatBalance();
    tended.start();
    for (let t = 0; t < 10 && !tended.completed; t += 1 / 60) {
      if (tended.heat < 0.47) tended.stoke();
      tended.step(1 / 60);
    }
    expect(tended.success).toBe(true);
    expect(tended.failures).toBe(0);
  });
});

describe('bellows rhythm', () => {
  it('scores pumps in the window and misses beats that pass unpumped', () => {
    const puzzle = new BellowsRhythm();
    puzzle.start();
    puzzle.pump(); // phase 0: off the beat
    expect(puzzle.failures).toBe(1);
    run(puzzle, BellowsRhythm.BEAT * 0.5);
    expect(puzzle.inWindow()).toBe(true);
    puzzle.pump();
    expect(puzzle.pumps).toBe(1);
    // Let the next beat's window open and close without a pump.
    run(puzzle, BellowsRhythm.BEAT * 1.25);
    expect(puzzle.failures).toBe(2);
  });
});

describe('edge sharpening', () => {
  it('drifts off the edge unless nudged back', () => {
    const idle = new EdgeSharpening();
    idle.start();
    run(idle, 30);
    expect(idle.completed).toBe(true);
    expect(idle.success).toBe(false);

    const tended = new EdgeSharpening();
    tended.start();
    for (let t = 0; t < 10 && !tended.completed; t += 1 / 60) {
      if (tended.position > 0.05) tended.nudge(-1);
      else if (tended.position < -0.05) tended.nudge(1);
      tended.step(1 / 60);
    }
    expect(tended.success).toBe(true);
  });
});
