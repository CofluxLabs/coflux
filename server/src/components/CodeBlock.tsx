import classNames from "classnames";

type Props = {
  code: string[];
  className?: string;
};

export default function CodeBlock({ code, className }: Props) {
  return (
    <code
      className={classNames(
        "block whitespace-pre shadow-inner rounded-md p-2 my-2 text-sm",
        className,
      )}
    >
      {code.join("\n")}
    </code>
  );
}
