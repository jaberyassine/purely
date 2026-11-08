import { useParams } from 'react-router-dom';
import { CatalogView } from '../products/products';
export default function Search() { const { search = '' } = useParams(); return <CatalogView searchTerm={search} />; }