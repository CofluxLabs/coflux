import { ComponentType } from 'react';
import { IconAlertOctagonFilled, IconAlertTriangleFilled, IconInfoCircleFilled, IconSquareChevronRight, TablerIconsProps } from '@tabler/icons-react';
import classNames from 'classnames';

import * as models from '../models';

function iconForLevel(level: 0 | 1 | 2 | 3): [ComponentType<TablerIconsProps>, string] {
  switch (level) {
    case 0:
      return [IconSquareChevronRight, "text-gray-500"];
    case 1:
      return [IconInfoCircleFilled, "text-blue-500"];
    case 2:
      return [IconAlertTriangleFilled, "text-yellow-500"];
    case 3:
      return [IconAlertOctagonFilled, "text-red-600"];
  }
}

type Props = {
  message: models.LogMessage;
  size?: number;
  className?: string;
}

export default function LogMessage({ message, size = 16, className }: Props) {
  const [Icon, color] = iconForLevel(message.level);
  return (
    <div className={className}>
      <Icon size={size} className={classNames("inline-block mr-1", color)} />
      {message.message}
    </div>
  );
}
