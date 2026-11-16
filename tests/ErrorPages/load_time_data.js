const loadTimeData = {
  data_: null,
  set data(value) {
    this.data_ = value;
  },
  get data() {
    return this.data_;
  },
  valueExists(id) {
    return !!this.data_ && id in this.data_;
  },
  getValue(id) {
    if (!this.valueExists(id)) {
      throw new Error(`loadTimeData has no value for ${id}`);
    }
    return this.data_[id];
  },
  getString(id) {
    const value = this.getValue(id);
    if (typeof value !== 'string') {
      throw new Error(`${id} is not a string`);
    }
    return value;
  },
  getBoolean(id) {
    const value = this.getValue(id);
    if (typeof value !== 'boolean') {
      throw new Error(`${id} is not a boolean`);
    }
    return value;
  },
  getInteger(id) {
    return Number(this.getValue(id));
  },
};
