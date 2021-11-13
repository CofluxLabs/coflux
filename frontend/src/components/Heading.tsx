import React, { ReactNode } from 'react'
import classNames from 'classnames';

type Props = {
  className?: string;
  children: ReactNode;
}

export default function Heading({ className, children }: Props) {
  return <h1 className={classNames('text-2xl mt-2 mb-6 text-gray-900 tracking-tight', className)}>{children}</h1>
}
