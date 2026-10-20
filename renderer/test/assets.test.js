import { test } from 'node:test';
import assert from 'node:assert/strict';
import { localImageURL } from '../src/assets.js';

test('relative paths start at the document folder', () => {
  assert.equal(localImageURL('images/cover.png'), 'dotmd-asset://doc/images%2Fcover.png');
});

test('parent folders survive encoding', () => {
  assert.equal(localImageURL('../../assets/a b.png'), 'dotmd-asset://doc/..%2F..%2Fassets%2Fa%20b.png');
});

test('a leading slash starts at the watched folder', () => {
  assert.equal(localImageURL('/.github/assets/cover.png'), 'dotmd-asset://root/.github%2Fassets%2Fcover.png');
});

test('percent escapes and queries are handled', () => {
  assert.equal(localImageURL('my%20image.png?raw=true'), 'dotmd-asset://doc/my%20image.png');
});

test('web, data and anchor URLs are left alone', () => {
  for (const src of ['https://example.com/a.png', 'data:image/png;base64,AAAA', '#top', '//cdn.example.com/a.png', '']) {
    assert.equal(localImageURL(src), null);
  }
});
