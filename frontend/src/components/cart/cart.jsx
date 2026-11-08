import { useContext, useEffect, useRef } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { FiX, FiPlus, FiMinus, FiTrash2, FiShoppingBag, FiArrowRight } from 'react-icons/fi';
import CartContext from '../../contexts/cart.contect';
import { AuthContext } from '../../contexts/auth.context';
export default function Cart({ isCartOpen, onClose }) {
  const { cart, cartError, isProcessingCart, addItemToCart, removeItemFromCart } = useContext(CartContext);
  const { user } = useContext(AuthContext);
  const navigate = useNavigate();
  const panel = useRef(null);
  useEffect(() => {
    if (!isCartOpen) return;
    const previous = document.body.style.overflow;
    document.body.style.overflow = 'hidden';
    panel.current?.querySelector('button')?.focus();
    return () => { document.body.style.overflow = previous; };
  }, [isCartOpen]);
  if (!isCartOpen) return null;
  const items = cart.cartItems || [];
  const trap = event => {
    if (event.key !== 'Tab') return;
    const focusable = [...panel.current.querySelectorAll('button:not([disabled]),a[href]')];
    const first = focusable[0], last = focusable[focusable.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last?.focus(); }
    else if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first?.focus(); }
  };
  return <div className="bag-overlay"><button className="bag-backdrop" onClick={onClose} aria-label="Close shopping bag" tabIndex={-1} /><aside className="bag-panel" ref={panel} role="dialog" aria-modal="true" aria-labelledby="bag-title" onKeyDown={trap}>
    <div className="bag-heading"><div><span className="eyebrow">YOUR EVERYDAY PICKS</span><h2 id="bag-title">The good stuff.</h2></div><button className="icon-button" onClick={onClose} aria-label="Close shopping bag"><FiX /></button></div>
    {cartError && user && <p className="bag-error" role="alert">We couldn't update your bag. Please try again.</p>}
    {!items.length ? <div className="empty-bag"><FiShoppingBag /><h3>A little room for good things.</h3><p>{user ? 'Find your next everyday essential.' : 'Sign in to start your own collection.'}</p><Link className="primary-link" onClick={onClose} to={user ? '/products/All' : '/auth/login'}>{user ? 'Explore the collection' : 'Sign in'}<FiArrowRight /></Link></div> :
      <div className="bag-items" aria-busy={isProcessingCart}>{items.map(item => <article className="bag-item" key={item.productId}><img src={item.imageUrl} alt={item.productName} /><div><h3>{item.productName}</h3><p>Rs. {Number(item.price).toFixed(2)}</p><div className="bag-quantity"><button aria-label={'Decrease ' + item.productName + ' quantity'} disabled={isProcessingCart || item.quantity <= 1} onClick={() => addItemToCart(item.productId, -1)}><FiMinus /></button><span>{item.quantity}</span><button aria-label={'Increase ' + item.productName + ' quantity'} disabled={isProcessingCart || item.quantity >= 20} onClick={() => addItemToCart(item.productId, 1)}><FiPlus /></button><button className="bag-remove" aria-label={'Remove ' + item.productName} disabled={isProcessingCart} onClick={() => removeItemFromCart(item.productId)}><FiTrash2 /></button></div></div></article>)}</div>}
    {!!items.length && <div className="bag-total"><div><span>Subtotal</span><strong>Rs. {Number(cart.subtotal).toFixed(2)}</strong></div><p>Demo checkout. No payment is collected.</p><button className="primary-link" disabled={isProcessingCart} onClick={() => { onClose(); navigate('/order/checkout'); }}>Continue to checkout <FiArrowRight /></button></div>}
  </aside></div>;
}