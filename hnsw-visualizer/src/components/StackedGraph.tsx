import React from 'react';
import { HNSWNode } from '../lib/hnsw';

interface StackedGraphProps {
  nodes: HNSWNode[];
  maxLevel: number;
  width: number;
  height: number;
}

export const StackedGraph: React.FC<StackedGraphProps> = ({ nodes, maxLevel, width, height }) => {
  const layerOffset = 50;
  const perspectiveOffset = 20;

  return (
    <svg width={width} height={height + maxLevel * layerOffset} style={{ border: '1px solid #ccc', backgroundColor: '#f9f9f9' }}>
      {Array.from({ length: maxLevel + 1 }).map((_, level) => {
        const yOffset = (maxLevel - level) * layerOffset;
        const xOffset = level * perspectiveOffset;
        const nodesAtLevel = nodes.filter(node => node.level >= level);

        return (
          <g key={level} transform={`translate(${xOffset}, ${yOffset})`}>
            {/* Draw layer plane */}
            <rect 
              width={width - maxLevel * perspectiveOffset} 
              height={height} 
              fill="white" 
              fillOpacity="0.3" 
              stroke="#eee" 
            />
            <text x="5" y="15" fontSize="12" fill="#999">Level {level}</text>

            {/* Draw edges */}
            {nodesAtLevel.map((node) => {
              const neighbors = node.neighbors[level] || [];
              const nodeIndex = nodes.indexOf(node);
              return neighbors.map(neighborIndex => {
                if (nodeIndex < neighborIndex) {
                  const neighbor = nodes[neighborIndex];
                  return (
                    <line
                      key={`${level}-${node.id}-${neighbor.id}`}
                      x1={node.vector[0] * 0.8}
                      y1={node.vector[1] * 0.8}
                      x2={neighbor.vector[0] * 0.8}
                      y2={neighbor.vector[1] * 0.8}
                      stroke="#ccc"
                      strokeWidth="1"
                    />
                  );
                }
                return null;
              });
            })}

            {/* Draw nodes */}
            {nodesAtLevel.map(node => (
              <circle
                key={`${level}-${node.id}`}
                cx={node.vector[0] * 0.8}
                cy={node.vector[1] * 0.8}
                r="3"
                fill={node.level === level ? '#007bff' : '#6c757d'}
              />
            ))}

            {/* Draw cross-layer connections to the same node in the layer below */}
            {level > 0 && nodesAtLevel.map(node => (
               <line
                 key={`cross-${level}-${node.id}`}
                 x1={node.vector[0] * 0.8}
                 y1={node.vector[1] * 0.8}
                 x2={node.vector[0] * 0.8 - perspectiveOffset}
                 y2={node.vector[1] * 0.8 + layerOffset}
                 stroke="#007bff"
                 strokeWidth="0.5"
                 strokeDasharray="2,2"
                 opacity="0.3"
               />
            ))}
          </g>
        );
      })}
    </svg>
  );
};
