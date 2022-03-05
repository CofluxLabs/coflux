import { createElement, StrictMode } from 'react';
import ReactDOM from 'react-dom';
import App from './App';

import './index.css';

ReactDOM.render(
  createElement(StrictMode, null, createElement(App)),
  document.getElementById('root')
);
