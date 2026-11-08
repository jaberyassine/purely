import { Link } from 'react-router-dom';
import { FiArrowRight, FiSun } from 'react-icons/fi';
export default function Hero() {
  return <section className="wellness-hero">
    <div className="hero-copy"><span className="eyebrow"><span /> THE EVERYDAY WELLNESS EDIT</span>
      <h1>Feel good.<br />Live <em>purely.</em></h1>
      <p>Small rituals, thoughtfully chosen essentials. Find a little more balance in the way you move, unwind, and care for yourself.</p>
      <Link className="primary-link" to="/products/All">Find your feel-good <FiArrowRight /></Link>
      <div className="hero-footnote"><FiSun /><span>A little something for your everyday.</span></div>
    </div>
    <div className="hero-visual"><img src="/categories/6773f28a0f5832bdbc95ebbd.jpg" alt="Yoga mat, dumbbells and everyday movement essentials" fetchPriority="high" />
      <span className="hero-stamp">MOVE WELL<br /><span>feel good</span><br />EVERY DAY</span>
      <div className="hero-caption"><span>01 / MAKE YOUR MOVE</span><span>Good habits start small. <FiArrowRight /></span></div>
    </div>
  </section>;
}