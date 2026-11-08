export function selectProducts(products, categories, { category = 'All', searchTerm, sort = 'collection' } = {}) {
  const current = categories.find(item => item.categoryName === category);
  const query = searchTerm?.trim().toLocaleLowerCase();
  const list = products.filter(product => query !== undefined ?
    [product.productName, product.categoryName, product.description].join(' ').toLocaleLowerCase().includes(query) :
    category === 'All' || product.categoryId === current?.id);
  if (sort === 'low') list.sort((a, b) => Number(a.price) - Number(b.price));
  if (sort === 'high') list.sort((a, b) => Number(b.price) - Number(a.price));
  if (sort === 'name') list.sort((a, b) => a.productName.localeCompare(b.productName));
  return list;
}
