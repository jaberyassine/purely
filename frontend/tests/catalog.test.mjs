import test from 'node:test';
import assert from 'node:assert/strict';
import { selectProducts } from '../src/lib/catalog.mjs';
const categories = [{ id: 'care', categoryName: 'Personal Care' }, { id: 'fitness', categoryName: 'Fitness Equipment' }];
const products = [
  { id: 'mat', productName: 'Yoga Mat', categoryId: 'fitness', categoryName: 'Fitness Equipment', price: 25, description: 'For movement' },
  { id: 'cream', productName: 'Hand Cream', categoryId: 'care', categoryName: 'Personal Care', price: 8, description: 'Everyday care' },
  { id: 'ring', productName: 'Pilates Ring', categoryId: 'fitness', categoryName: 'Fitness Equipment', price: 22, description: 'For movement' },
];
test('a refreshed category URL resolves from the catalog without navigation state', () => {
  assert.deepEqual(selectProducts(products, categories, { category: 'Fitness Equipment' }).map(item => item.id), ['mat', 'ring']);
  assert.deepEqual(selectProducts(products, [], { category: 'Fitness Equipment' }), []);
});
test('sorting works numerically and leaves the source collection intact', () => {
  assert.deepEqual(selectProducts(products, categories, { sort: 'low' }).map(item => item.price), [8, 22, 25]);
  assert.deepEqual(selectProducts(products, categories, { sort: 'high' }).map(item => item.price), [25, 22, 8]);
  assert.deepEqual(products.map(item => item.id), ['mat', 'cream', 'ring']);
});
test('search is case-insensitive and finds both names and categories', () => {
  assert.deepEqual(selectProducts(products, categories, { searchTerm: '  YOGA ' }).map(item => item.id), ['mat']);
  assert.deepEqual(selectProducts(products, categories, { searchTerm: 'personal care' }).map(item => item.id), ['cream']);
  assert.deepEqual(selectProducts(products, categories, { searchTerm: 'unknown item' }), []);
});
test('unknown categories do not accidentally expose the entire collection', () => {
  assert.deepEqual(selectProducts(products, categories, { category: 'Unavailable' }), []);
  assert.equal(selectProducts(products, categories).length, 3);
});
