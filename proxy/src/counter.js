// A Durable Object is single-threaded per instance, so read-modify-write here is atomic.
// Workers KV is not: three concurrent requests all read the same value and all write value+1,
// which lost two of every three increments and left the daily caps roughly 3x looser than set.

const DAY_SECONDS = 86_400;

export class SpendCounter {
  constructor(state) {
    this.state = state;
    // The runtime's input gate already serializes storage, but the chain makes that guarantee
    // explicit and local: correctness here should not depend on a platform detail.
    this.queue = Promise.resolve();
  }

  /**
   * Body: [{ key, limit }, ...]. Charges one unit against every key, all or nothing.
   * 200 with the first key's new count, or 429 when any key is already at its limit.
   */
  async fetch(request) {
    const pairs = await request.json();
    const run = this.queue.then(() => this.charge(pairs), () => this.charge(pairs));
    this.queue = run.then(() => {}, () => {});
    return run;
  }

  async charge(pairs) {
    const counts = [];
    for (const { key, limit } of pairs) {
      const current = Number(await this.state.storage.get(key)) || 0;
      if (current >= limit) return new Response('quota', { status: 429 });
      counts.push([key, current + 1]);
    }
    for (const [key, next] of counts) await this.state.storage.put(key, next);

    // Yesterday's keys are never read again; drop them a day after this object first wakes.
    await this.state.storage.setAlarm?.(Date.now() + DAY_SECONDS * 1000);
    return new Response(String(counts[0][1]));
  }

  async alarm() {
    await this.state.storage.deleteAll?.();
  }
}
