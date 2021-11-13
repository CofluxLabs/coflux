import classNames from 'classnames';

type Intent = 'success' | 'danger' | 'warning' | 'info';

function classNameForIntent(intent: Intent) {
  switch (intent) {
    case 'success':
      return 'bg-green-200 text-green-900';
    case 'danger':
      return 'bg-red-200 text-red-900';
    case 'warning':
      return 'bg-yellow-200 text-yellow-900';
    case 'info':
      return 'bg-blue-200 text-blue-900';
  }
}

type Props = {
  label: string;
  intent: Intent
}

export default function Badge({ label, intent }: Props) {
  return (
    <span className={classNames('rounded px-2 py-1 text-sm uppercase font-bold', classNameForIntent(intent))}>
      {label}
    </span>
  )
}