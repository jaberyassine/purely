import { useContext, useState } from 'react';
import { useNavigate, Link } from 'react-router-dom';
import { FiPlus, FiCheck, FiImage, FiArrowRight } from 'react-icons/fi';
import CartContext from '../../contexts/cart.contect';
import { AuthContext } from '../../contexts/auth.context';

export function ProductCard({ product }) {
  const { addItemToCart } = useContext(CartContext);
  const { user } = useContext(AuthContext);
  const navigate = useNavigate();
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState('');
  const [broken, setBroken] = useState(false);
  const add = async () => {
    if (!user?.token) { void navigate('/auth/login'); return; }
    setBusy(true); setMessage('');
    try {
      const success = await addItemToCart(product.id, 1);
      setMessage(success ? 'Added to your bag' : 'Could not add item. Please try again.');
    } catch { setMessage('Could not add item. Please try again.'); }
    finally { setBusy(false); }
  };
  return <article className="product-card">
    <div className="product-photo">{broken || !product.imageUrl ? <span className="photo-unavailable"><FiImage />Photo unavailable</span> : <img src={product.imageUrl} alt={product.productName} loading="lazy" onError={() => setBroken(true)} />}
      <span className="product-category">{product.categoryName}</span>
    </div>
    <div className="product-details"><h3>{product.productName}</h3><div className="product-bottom"><span className="product-amount"><small>Rs.</small> {Number(product.price).toFixed(2)}</span>
      <button className="add-to-bag" disabled={busy} onClick={add} aria-label={(busy ? 'Adding ' : 'Add to bag: ') + product.productName}>{busy ? 'Adding…' : message === 'Added to your bag' ? <><FiCheck /> Added</> : <><FiPlus /> Add to bag</>}</button>
    </div><span className="product-feedback" role="status">{message}</span></div>
  </article>;
}
export default function ProductGrid({ products, loading, error }) {
  if (loading) return <div className="product-grid" aria-busy="true" aria-label="Loading products">{[0,1,2,3].map(i => <div key={i} className="product-skeleton"><div /><span /><span /></div>)}</div>;
  if (error) return <div className="catalog-empty" role="status"><h2>A little pause.</h2><p>We couldn't load the collection. Please refresh to try again.</p></div>;
  if (!products.length) return <div className="catalog-empty" role="status"><FiSearchEmpty /><h2>Nothing here just yet.</h2><p>Try another collection or a different search.</p><Link className="inline-link" to="/products/All">Explore all essentials <FiArrowRight /></Link></div>;
  return <div className="product-grid">{products.map(product => <ProductCard key={product.id} product={product} />)}</div>;
}
function FiSearchEmpty() { return <FiImage size={28} aria-hidden="true" />; }