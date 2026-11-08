import { useMemo, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { FiSliders } from 'react-icons/fi';
import Header from '../../components/header/header';
import Footer from '../../components/footer/footer';
import ProductGrid from '../../components/product-grid/product-grid';
import useCatalog from '../../hooks/useCatalog';
import { selectProducts } from '../../lib/catalog.mjs';

export default function Products() { return <CatalogView />; }
export function CatalogView({ searchTerm }) {
  const { category = 'All' } = useParams();
  const { products, categories, loading, error } = useCatalog();
  const [sort, setSort] = useState('collection');
  const searching = searchTerm !== undefined;
  const selection = useMemo(() => selectProducts(products, categories, { category, searchTerm, sort }), [products, categories, category, searchTerm, sort]);
  return <><Header /><main id="page-content" className="catalog-page store-main">
    <div className="catalog-intro"><div className="breadcrumbs"><Link to="/">Home</Link><span>/</span><span>{searching ? 'Search' : 'The collection'}</span></div>
      <span className="eyebrow">{searching ? 'FIND YOUR FEEL-GOOD' : 'THOUGHTFULLY CHOSEN. SIMPLY ENJOYED.'}</span>
      <h1>{searching ? <>Results for <em>“{searchTerm}”</em></> : category === 'All' ? <>Your everyday <em>essentials.</em></> : category}</h1>
      <p>{searching ? 'A little closer to your next everyday favourite.' : 'For movement, moments of calm, and everything in between.'}</p>
    </div>
    {!searching && <nav className="collection-filters" aria-label="Product collections"><Link className={category === 'All' ? 'selected' : ''} to="/products/All" aria-current={category === 'All' ? 'page' : undefined}>All essentials</Link>{categories.map(item => <Link key={item.id} className={category === item.categoryName ? 'selected' : ''} aria-current={category === item.categoryName ? 'page' : undefined} to={'/products/' + encodeURIComponent(item.categoryName)}>{item.categoryName}</Link>)}</nav>}
    <section className="catalog-results" aria-label="Products"><div className="catalog-toolbar"><span role="status">{loading ? 'Finding your essentials…' : selection.length + ' essentials to explore'}</span><label><FiSliders /> Sort by <select value={sort} onChange={e => setSort(e.target.value)}><option value="collection">Collection order</option><option value="low">Price: low to high</option><option value="high">Price: high to low</option><option value="name">Name: A to Z</option></select></label></div><ProductGrid products={selection} loading={loading} error={error} /></section>
  </main><Footer /></>;
}
