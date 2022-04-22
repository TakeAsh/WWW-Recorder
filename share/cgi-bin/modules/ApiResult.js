class ApiResult {
  constructor(text) {
    const result = JSON.parse(text);
    if (result.hasOwnProperty('FileName*')) {
      result['FileName*'] = decodeURIComponent(result['FileName*'].replace(/^UTF-8''/i, ''));
    }
    Object.keys(result).forEach(key => this[key] = result[key]);
  }
}

export { ApiResult };
