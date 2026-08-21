import { useVirtualizer } from "@tanstack/react-virtual";
import { useMemo, useRef } from "react";
import type { ReactNode } from "react";

const DEFAULT_ESTIMATE = 140;
const CONTROL_ESTIMATE = 44;
const TAIL_ESTIMATE = 36;
const OVERSCAN = 8;

export interface VirtualChatFlowItem {
  readonly key: string;
  readonly kind: "control" | "node" | "tail";
  readonly nodeKey?: string;
  readonly content: ReactNode;
}

interface VirtualChatFlowProps {
  readonly items: readonly VirtualChatFlowItem[];
  readonly estimateNodeSize?: (nodeKey: string) => number;
}

/**
 * The conversation flow's only DOM window. Items keep their business keys;
 * scrolling merely changes which keyed seats are mounted. The caller owns the
 * node renderer, so virtualization cannot alter tool/message semantics.
 */
export function VirtualChatFlow({
  items,
  estimateNodeSize,
}: VirtualChatFlowProps) {
  const flowRef = useRef<HTMLDivElement | null>(null);
  const estimateSize = (index: number): number => {
    const item = items[index];
    if (item?.kind === "node" && item.nodeKey !== undefined)
      return estimateNodeSize?.(item.nodeKey) ?? DEFAULT_ESTIMATE;
    return item?.kind === "control" ? CONTROL_ESTIMATE : TAIL_ESTIMATE;
  };

  const virtualizer = useVirtualizer<HTMLDivElement, HTMLDivElement>({
    count: items.length,
    getScrollElement: () => {
      const flow = flowRef.current;
      return flow?.closest<HTMLElement>('[data-conversation-scroll]') ?? flow?.parentElement ?? null
    },
    estimateSize,
    getItemKey: (index) => items[index]?.key ?? index,
    measureElement: (element) => element.getBoundingClientRect().height,
    overscan: OVERSCAN,
  });

  const virtualItems = virtualizer.getVirtualItems();
  const totalSize = virtualizer.getTotalSize();
  const rendered = useMemo(
    () =>
      virtualItems.flatMap((item) => {
        const flowItem = items[item.index];
        return flowItem === undefined ? [] : [{ item, flowItem }];
      }),
    [items, virtualItems],
  );

  return (
    <div
      ref={flowRef}
      data-chat-virtual-flow=""
      style={{ position: "relative", width: "100%", height: totalSize }}
    >
      {rendered.map(({ item, flowItem }) => (
        <div
          key={flowItem.key}
          ref={virtualizer.measureElement}
          data-chat-virtual-index={item.index}
          data-chat-virtual-key={flowItem.key}
          style={{
            position: "absolute",
            top: 0,
            left: 0,
            width: "100%",
            paddingBottom: 16,
            transform: `translateY(${item.start}px)`,
          }}
        >
          {flowItem.content}
        </div>
      ))}
    </div>
  );
}
