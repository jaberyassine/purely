import { Link } from 'react-router-dom';
import { FiArrowUpRight } from 'react-icons/fi';
import useCatalog from '../../hooks/useCatalog';
import ProductGrid from '../product-grid/product-grid';
export default function Featured() {
  const { products, loading, error } = useCatalog();
  const picks = ['Yoga Mat', 'Face Moisturizer', 'Stainless Steel Water Bottle', 'Vanilla Scented Candle'];
  const featured = products.filter(product => picks.includes(product.productName));
  const selection = [...featured, ...products.filter(product => !picks.includes(product.productName))].slice(0, 4);
  return <section className="store-section featured-section"><div className="section-heading"><div><span className="eyebrow">MEET YOUR NEXT RITUAL</span><h2>Everyday, made better.</h2></div><Link className="inline-link" to="/products/All">View the collection <FiArrowUpRight /></Link></div><ProductGrid products={selection} loading={loading} error={error} /></section>;
}