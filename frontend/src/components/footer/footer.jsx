import { Link } from 'react-router-dom';
import { FiArrowUpRight } from 'react-icons/fi';
import Logo from '../logo/logo';
export default function Footer() {
  return <footer className="site-footer"><div className="footer-main"><div className="footer-brand"><Logo /><p>A little more balance.<br />A little more everyday joy.</p></div><div><h3>Take a look around</h3><Link to="/products/All">Shop all essentials <FiArrowUpRight /></Link><Link to="/#our-story">Our approach</Link></div><div><h3>Your space</h3><Link to="/auth/login">Sign in</Link><Link to="/auth/register">Create an account</Link><Link to="/my/account">My orders</Link></div><div className="footer-note"><span className="eyebrow">GOOD TO KNOW</span><p>This is a demonstration store. Products and prices are illustrative. No payments are collected.</p></div></div><div className="footer-bottom"><span>© {new Date().getFullYear()} Purely. Made for the everyday.</span><span>Move. Nourish. Unwind.</span></div></footer>;
}