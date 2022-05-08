class ApiResult {
  constructor(data) {
    const result = (typeof data == 'string')
      ? JSON.parse(data)
      : data;
    if (result.hasOwnProperty('FileName*')) {
      result['FileName*'] = decodeURIComponent(result['FileName*'].replace(/^UTF-8''/i, ''));
    }
    Object.assign(this, result);
  }
}

export { ApiResult };
