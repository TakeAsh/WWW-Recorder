class CyclicEnum extends Array {
  constructor(...args) {
    super();
    args.forEach((key, index) => Object.defineProperty(this, key, {
      value: this[index] = Object.freeze({
        toString: () => key,
        index: index,
        next: () => this[(index + 1) % args.length],
      }),
      enumerable: false,
    }));
    Object.freeze(this);
  }

  static get [Symbol.species]() { return Array; }

  get(key) {
    return this.hasOwnProperty(key) ?
      this[key] :
      this[0];
  }
}

export { CyclicEnum };
