import { useState, useCallback, useRef } from 'react';
import { HNSW, HNSWConfig, Vector, HNSWNode, HNSWStep } from '../lib/hnsw';

export function useHNSW(config?: Partial<HNSWConfig>) {
  const [hnsw] = useState(() => new HNSW(config));
  const [nodes, setNodes] = useState<HNSWNode[]>([]);
  const [maxLevel, setMaxLevel] = useState(-1);
  const [entryPoint, setEntryPoint] = useState(-1);
  const [currentStep, setCurrentStep] = useState<HNSWStep | null>(null);
  const [isStepping, setIsStepping] = useState(false);

  const stepIterator = useRef<Generator<HNSWStep, void> | null>(null);

  const startAddPointStep = useCallback((vector: Vector, id: string) => {
    stepIterator.current = hnsw.addStep(vector, id);
    setIsStepping(true);
    nextStep();
  }, [hnsw]);

  const nextStep = useCallback(() => {
    if (stepIterator.current) {
      const result = stepIterator.current.next();
      if (!result.done) {
        setCurrentStep(result.value);
        setNodes([...hnsw.nodes]);
        setMaxLevel(hnsw.maxLevel);
        setEntryPoint(hnsw.entryPoint);
      } else {
        setIsStepping(false);
        setCurrentStep(null);
        stepIterator.current = null;
      }
    }
  }, [hnsw]);

  const addPoint = useCallback((vector: Vector, id: string) => {
    hnsw.add(vector, id);
    setNodes([...hnsw.nodes]);
    setMaxLevel(hnsw.maxLevel);
    setEntryPoint(hnsw.entryPoint);
  }, [hnsw]);

  return {
    nodes,
    maxLevel,
    entryPoint,
    currentStep,
    isStepping,
    addPoint,
    startAddPointStep,
    nextStep,
    config: hnsw.config
  };
}
