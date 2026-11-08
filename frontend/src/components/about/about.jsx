import { Link } from 'react-router-dom';
import { FiArrowUpRight } from 'react-icons/fi';
export default function About() {
  return <section className="slow-moments" id="our-story">
    <div className="slow-photo"><img src="/categories/6773f28a0f5832bdbc95ebc0.jpg" alt="A quiet moment at the beach at sunset" loading="lazy" /></div>
    <div className="slow-copy"><span className="eyebrow">LESS RUSH. MORE YOU.</span><h2>Make room for<br />the little things.</h2><p>A stretch before your day begins. A moment to yourself at the end of it. Wellness doesn't need to be complicated. Start with what feels right for you.</p><Link className="inline-link" to="/products/All">Discover your next ritual <FiArrowUpRight /></Link></div>
  </section>;
}