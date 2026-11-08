import { useContext, useEffect, useRef, useState } from 'react';
import { Link, NavLink, useNavigate } from 'react-router-dom';
import { FiSearch, FiShoppingBag, FiUser, FiMenu, FiX, FiArrowUpRight } from 'react-icons/fi';
import Logo from '../logo/logo';
import Cart from '../cart/cart';
import CartContext from '../../contexts/cart.contect';
import { AuthContext } from '../../contexts/auth.context';

export default function Header() {
  const navigate = useNavigate();
  const { cart, getCartInformation, clearCart } = useContext(CartContext);
  const { user, toggleUser } = useContext(AuthContext);
  const [menu, setMenu] = useState(false);
  const [cartOpen, setCartOpen] = useState(false);
  const [query, setQuery] = useState('');
  const cartButton = useRef(null);
  useEffect(() => {
    if (!cartOpen && !menu) return;
    const close = event => { if (event.key === 'Escape') { setMenu(false); setCartOpen(false); cartButton.current?.focus(); } };
    document.addEventListener('keydown', close);
    return () => document.removeEventListener('keydown', close);
  }, [cartOpen, menu]);
  const search = event => {
    event.preventDefault();
    if (query.trim()) { void navigate('/search/' + encodeURIComponent(query.trim())); setMenu(false); }
  };
  const logout = () => { localStorage.removeItem('user'); clearCart(); toggleUser(); void navigate('/'); setMenu(false); };
  const closeCart = () => { setCartOpen(false); cartButton.current?.focus(); };
  return <>
    <a className="skip-link" href="#page-content">Skip to content</a>
    <div className="announcement">A little care. A better everyday. <Link to="/products/All">Explore the collection <FiArrowUpRight /></Link></div>
    <header className="site-header"><div className="header-inner">
      <Logo />
      <nav className={'main-nav' + (menu ? ' is-open' : '')} aria-label="Main navigation">
        <NavLink to="/" end onClick={() => setMenu(false)}>Home</NavLink>
        <NavLink to="/products/All" onClick={() => setMenu(false)}>Shop all</NavLink>
        <Link to="/#our-story" onClick={() => setMenu(false)}>Our approach</Link>
        {user && <button className="text-button mobile-logout" onClick={logout}>Sign out</button>}
      </nav>
      <form className="header-search" onSubmit={search} role="search">
        <input aria-label="Search products" type="search" placeholder="Find your everyday essentials" value={query} onChange={e => setQuery(e.target.value)} />
        <button aria-label="Search" type="submit"><FiSearch /></button>
      </form>
      <div className="header-actions">
        <Link className="icon-button" to={user ? '/my/account' : '/auth/login'} aria-label={user ? 'My account' : 'Sign in'}><FiUser /></Link>
        {user && <button className="text-button desktop-logout" onClick={logout}>Sign out</button>}
        <button className="icon-button bag-button" ref={cartButton} aria-label={'Open shopping bag, ' + (cart.noOfCartItems || 0) + ' items'} onClick={() => { getCartInformation(); setCartOpen(true); }}><FiShoppingBag /><span>{cart.noOfCartItems || 0}</span></button>
        <button className="icon-button menu-button" aria-label={menu ? 'Close navigation' : 'Open navigation'} aria-expanded={menu} onClick={() => setMenu(!menu)}>{menu ? <FiX /> : <FiMenu />}</button>
      </div>
    </div></header>
    <Cart isCartOpen={cartOpen} onClose={closeCart} />
  </>;
}
