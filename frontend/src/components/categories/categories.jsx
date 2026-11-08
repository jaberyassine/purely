import { useEffect } from 'react';
import { Link } from 'react-router-dom';
import { FiArrowUpRight } from 'react-icons/fi';
import ProductService from '../../api-service/product.service';

export function categoryImage(image) {
  if (!image) return null;
  return image.startsWith('/') || image.startsWith('https://') ? image : '/categories/' + image;
}
export default function Categories() {
  const { getAllCategories, categories, isLoading, error } = ProductService();
  useEffect(() => { void getAllCategories(); }, []);
  const collections = categories.filter(item => !item.categoryName.startsWith('Demo Wellness'));
  return <section className="store-section collections-section" aria-labelledby="collections-title">
    <div className="section-heading"><div><span className="eyebrow">A PLACE TO START</span><h2 id="collections-title">Your kind of wellness.</h2></div><Link className="inline-link" to="/products/All">Explore everything <FiArrowUpRight /></Link></div>
    {isLoading && <p className="quiet-state">Finding your collections…</p>}
    {error && <p role="status" className="quiet-state">Collections are taking a moment. <Link to="/products/All">Browse the shop</Link></p>}
    <div className="collection-grid">{collections.map((item, index) => <Link className="collection-card" to={'/products/' + encodeURIComponent(item.categoryName)} state={{ categoryId: item.id }} key={item.id}>
      <div className="collection-image">{categoryImage(item.imageUrl) && <img src={categoryImage(item.imageUrl)} alt="" loading="lazy" onError={event => { event.currentTarget.style.visibility = 'hidden'; }} />}<span>0{index + 1}</span></div>
      <h3>{item.categoryName}<FiArrowUpRight /></h3>
    </Link>)}</div>
  </section>;
}
