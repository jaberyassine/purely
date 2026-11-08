import { Link } from 'react-router-dom';
import { PiPlantLight } from 'react-icons/pi';
import './logo.css';
export default function Logo() {
  return <Link to="/" className="brand" aria-label="Purely home"><PiPlantLight aria-hidden="true" /><span>purely<span className="brand-dot">.</span></span></Link>;
}