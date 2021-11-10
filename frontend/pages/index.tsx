import React, { Fragment } from 'react';
import Head from 'next/head';

import Hello from '../components/Hello';

export default function Home() {
  return (
    <Fragment>
      <Head>
        <title>Coflux</title>
      </Head>
      <Hello />
    </Fragment>
  );
}
