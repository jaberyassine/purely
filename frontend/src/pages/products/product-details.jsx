import { useEffect, useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import axios from 'axios';
import API_BASE_URL from '../../api-service/apiConfig';
import Header from '../../components/header/header';
import Footer from '../../components/footer/footer';
import { ProductCard } from '../../components/product-grid/product-grid';

export default function ProductDetails() {
  const { id } = useParams();
  return <><Header /><main id="page-content" className="catalog-page store-main">
    <div className="breadcrumbs"><Link to="/products/All">Back to the collection</Link></div>
    <ProductDetailsContent key={id} id={id} />
  </main><Footer /></>;
}

function ProductDetailsContent({ id }) {
  const [result, setResult] = useState(null);
  useEffect(() => {
    const controller = new AbortController();
    axios.get(API_BASE_URL + '/product-service/product/get/byId', {
      params: { id },
      signal: controller.signal,
      timeout: 10000,
    }).then(({ data }) => {
      if (!controller.signal.aborted) setResult({ product: data.success && data.response });
    }).catch(() => {
      if (!controller.signal.aborted) setResult({ product: null });
    });
    return () => controller.abort();
  }, [id]);

  if (!result) return <p role="status">Loading product…</p>;
  if (!result.product) return <p role="status">This product could not be loaded.</p>;
  return <div className="product-detail-view"><ProductCard product={result.product} detail /></div>;
}
