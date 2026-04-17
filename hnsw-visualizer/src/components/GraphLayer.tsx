import React from 'react';
import { HNSWNode, HNSWStep } from '../lib/hnsw';

interface GraphLayerProps {
  nodes: HNSWNode[];
  level: number;
  width: number;
  height: number;
  showEdges?: boolean;
  currentStep?: HNSWStep | null;
  onLayerClick?: (x: number, y: number) => void;
}

export const GraphLayer: React.FC<GraphLayerProps> = ({ nodes, level, width, height, showEdges = true, currentStep, onLayerClick }) => {
  const nodesAtLevel = nodes.filter(node => node.level >= level);
  
  const handleSvgClick = (e: React.MouseEvent<SVGSVGElement>) => {
    if (onLayerClick) {
      const rect = e.currentTarget.getBoundingClientRect();
      const x = e.clientX - rect.left;
      const y = e.clientY - rect.top;
      onLayerClick(x, y);
    }
  };

  const isHighlighted = (nodeIndex: number) => {
    if (!currentStep) return false;
    if (currentStep.type === 'search_layer_step' && currentStep.level === level) {
      return currentStep.current === nodeIndex || currentStep.candidates.includes(nodeIndex);
    }
    if (currentStep.type === 'search_layer_end' && currentStep.level === level) {
      return currentStep.nearest === nodeIndex;
    }
    return false;
  };

  return (
    <svg 
      width={width} 
      height={height} 
      onClick={handleSvgClick}
      style={{ border: '1px solid #ccc', backgroundColor: '#f9f9f9', cursor: 'crosshair' }}
    >
      {showEdges && nodesAtLevel.map((node) => {
        const neighbors = node.neighbors[level] || [];
        const nodeIndex = nodes.indexOf(node);
        return neighbors.map(neighborIndex => {
          if (nodeIndex < neighborIndex) {
            const neighbor = nodes[neighborIndex];
            return (
              <line
                key={`${node.id}-${neighbor.id}`}
                x1={node.vector[0]}
                y1={node.vector[1]}
                x2={neighbor.vector[0]}
                y2={neighbor.vector[1]}
                stroke="#aaa"
                strokeWidth="1"
              />
            );
          }
          return null;
        });
      })}
      
      {nodesAtLevel.map((node, idx) => {
        const nodeIndex = nodes.indexOf(node);
        const highlighted = isHighlighted(nodeIndex);
        return (
          <circle
            key={node.id}
            cx={node.vector[0]}
            cy={node.vector[1]}
            r={highlighted ? "6" : "4"}
            fill={highlighted ? '#ffc107' : (node.level === level ? '#007bff' : '#6c757d')}
            stroke={highlighted ? '#000' : 'none'}
            strokeWidth={highlighted ? 2 : 0}
          />
        );
      })}
    </svg>
  );
};
