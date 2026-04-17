export type Vector = [number, number];

export interface HNSWNode {
  id: string;
  vector: Vector;
  level: number;
  neighbors: number[][]; // neighbors[level] = list of node indices
}

export interface HNSWConfig {
  M: number;
  M0: number;
  efConstruction: number;
  mL: number;
}

export type HNSWStep = 
  | { type: 'search_layer_start'; level: number; entryPoint: number }
  | { type: 'search_layer_step'; level: number; current: number; candidates: number[] }
  | { type: 'search_layer_end'; level: number; nearest: number }
  | { type: 'connect_nodes'; level: number; nodeA: number; nodeB: number }
  | { type: 'shrink_neighbors'; level: number; node: number };

export class HNSW {
  nodes: HNSWNode[] = [];
  entryPoint: number = -1;
  maxLevel: number = -1;
  config: HNSWConfig;

  constructor(config: Partial<HNSWConfig> = {}) {
    this.config = {
      M: config.M || 16,
      M0: config.M0 || 32,
      efConstruction: config.efConstruction || 64,
      mL: config.mL || 1 / Math.log(16),
    };
  }

  distance(a: Vector, b: Vector): number {
    return Math.sqrt(Math.pow(a[0] - b[0], 2) + Math.pow(a[1] - b[1], 2));
  }

  getRandomLevel(): number {
    const level = Math.floor(-Math.log(Math.random()) * this.config.mL);
    return level;
  }

  *searchLayerStep(query: Vector, entryPoint: number, ef: number, level: number): Generator<HNSWStep, { nearest: number; candidates: { id: number; dist: number }[] }> {
    yield { type: 'search_layer_start', level, entryPoint };
    
    let visited = new Set<number>();
    visited.add(entryPoint);

    let candidates = [{ id: entryPoint, dist: this.distance(query, this.nodes[entryPoint].vector) }];
    let nearestNeighbors = [...candidates];

    while (candidates.length > 0) {
      candidates.sort((a, b) => a.dist - b.dist);
      let c = candidates.shift()!;

      yield { type: 'search_layer_step', level, current: c.id, candidates: nearestNeighbors.map(n => n.id) };

      const furthestInNearest = nearestNeighbors[nearestNeighbors.length - 1];
      if (c.dist > furthestInNearest.dist && nearestNeighbors.length >= ef) {
        break;
      }

      const neighbors = this.nodes[c.id].neighbors[level] || [];
      for (const neighborId of neighbors) {
        if (!visited.has(neighborId)) {
          visited.add(neighborId);
          const dist = this.distance(query, this.nodes[neighborId].vector);
          
          if (dist < furthestInNearest.dist || nearestNeighbors.length < ef) {
            candidates.push({ id: neighborId, dist });
            nearestNeighbors.push({ id: neighborId, dist });
            nearestNeighbors.sort((a, b) => a.dist - b.dist);
            if (nearestNeighbors.length > ef) {
              nearestNeighbors.pop();
            }
          }
        }
      }
    }

    yield { type: 'search_layer_end', level, nearest: nearestNeighbors[0].id };
    return { nearest: nearestNeighbors[0].id, candidates: nearestNeighbors };
  }

  *addStep(vector: Vector, id: string): Generator<HNSWStep, void> {
    const level = this.getRandomLevel();
    const newNodeIndex = this.nodes.length;
    const newNode: HNSWNode = {
      id,
      vector,
      level,
      neighbors: Array.from({ length: level + 1 }, () => []),
    };
    this.nodes.push(newNode);

    if (this.entryPoint === -1) {
      this.entryPoint = newNodeIndex;
      this.maxLevel = level;
      return;
    }

    let currEntryPoint = this.entryPoint;
    for (let l = this.maxLevel; l > level; l--) {
      const result = yield* this.searchLayerStep(vector, currEntryPoint, 1, l);
      currEntryPoint = result.nearest;
    }

    for (let l = Math.min(level, this.maxLevel); l >= 0; l--) {
      const { candidates } = yield* this.searchLayerStep(vector, currEntryPoint, this.config.efConstruction, l);
      
      const neighbors = candidates.slice(0, this.config.M);
      for (const neighbor of neighbors) {
        yield { type: 'connect_nodes', level: l, nodeA: newNodeIndex, nodeB: neighbor.id };
        this.nodes[newNodeIndex].neighbors[l].push(neighbor.id);
        this.nodes[neighbor.id].neighbors[l].push(newNodeIndex);
        
        const maxM = l === 0 ? this.config.M0 : this.config.M;
        if (this.nodes[neighbor.id].neighbors[l].length > maxM) {
          yield { type: 'shrink_neighbors', level: l, node: neighbor.id };
          this.shrinkNeighbors(neighbor.id, l, maxM);
        }
      }
      
      currEntryPoint = neighbors[0].id;
    }

    if (level > this.maxLevel) {
      this.maxLevel = level;
      this.entryPoint = newNodeIndex;
    }
  }

  shrinkNeighbors(nodeIndex: number, level: number, maxM: number) {
    const neighbors = this.nodes[nodeIndex].neighbors[level];
    const nodeVector = this.nodes[nodeIndex].vector;
    
    const neighborDistances = neighbors.map(id => ({
      id,
      dist: this.distance(nodeVector, this.nodes[id].vector)
    }));
    
    neighborDistances.sort((a, b) => a.dist - b.dist);
    this.nodes[nodeIndex].neighbors[level] = neighborDistances.slice(0, maxM).map(n => n.id);
  }

  // Keep non-generator versions for convenience
  add(vector: Vector, id: string) {
    const gen = this.addStep(vector, id);
    let res = gen.next();
    while (!res.done) {
      res = gen.next();
    }
  }

  search(query: Vector, k: number, ef: number): { id: number; dist: number }[] {
    if (this.entryPoint === -1) return [];

    let currEntryPoint = this.entryPoint;
    for (let l = this.maxLevel; l > 0; l--) {
      const gen = this.searchLayerStep(query, currEntryPoint, 1, l);
      let res = gen.next();
      while (!res.done) {
        res = gen.next();
      }
      currEntryPoint = (res.value as any).nearest;
    }

    const gen = this.searchLayerStep(query, currEntryPoint, ef, 0);
    let res = gen.next();
    while (!res.done) {
      res = gen.next();
    }
    return (res.value as any).candidates.slice(0, k);
  }
}
