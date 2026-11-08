import About from '../../components/about/about';
import Categories from '../../components/categories/categories';
import Footer from '../../components/footer/footer';
import Header from '../../components/header/header';
import Hero from '../../components/home_hero/hero';
import Featured from '../../components/featured/featured';
import { FiActivity, FiHeart, FiSun } from 'react-icons/fi';
export default function Home() {
  return <><Header /><main className="store-main" id="page-content"><Hero />
    <div className="ritual-strip"><span><FiActivity /> Move a little</span><span><FiHeart /> Care a little</span><span><FiSun /> Take a moment</span><span className="ritual-signature">It's the little things.</span></div>
    <Categories /><Featured /><About />
  </main><Footer /></>;
}