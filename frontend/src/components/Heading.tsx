import React, { ReactNode } from 'react'

type Props = {
  children: ReactNode;
}

export default function Heading({ children }: Props) {
  return <h1 className="text-2xl mt-2 mb-6 text-gray-900 tracking-tight">{children}</h1>
}
