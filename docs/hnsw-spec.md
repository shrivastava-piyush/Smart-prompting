# Specification: HNSW Interactive Learning Tool

## Objective
Build an interactive, web-based tool to help developers and students understand the **Hierarchical Navigable Small World (HNSW)** algorithm for approximate nearest neighbor search.

## Target Audience
- Developers learning about vector databases (e.g., Pinecone, Milvus, Weaviate).
- Computer Science students studying advanced data structures and graph algorithms.

## Key Features

### 1. Visualized Graph Layers
- **Hierarchical Representation:** Display the graph as multiple layers (Level 0 to Level L).
- **Dynamic Rendering:** Use Canvas or SVG to draw nodes and edges. Higher layers will show fewer nodes and longer "express" connections.
- **Layer Toggle:** Ability to view individual layers or a 3D-like stacked view.

### 2. Interactive Algorithm Execution
- **Step-by-Step Insertion:**
  - Visualize the search for the entry point in upper layers.
  - Show the selection of neighbors using the HNSW heuristic (diversity over pure distance).
  - Animate the creation of connections across layers.
- **Interactive Search:**
  - Animate a query point's path from the top layer down to the bottom.
  - Highlight visited nodes and the current candidate set (priority queue).

### 3. Parameter Playground
- **Adjustable Parameters:**
  - `M`: Maximum number of connections per node.
  - `efConstruction`: Size of the dynamic candidate list during construction.
  - `mL`: Multiplier for level generation (determines the probability of a node appearing in higher layers).
- **Real-time Rebuild:** Re-generate the graph instantly when parameters change to see structural impact.

### 4. Educational Content
- **Glossary:** Definitions of NSW, Small World property, Greedy Search, and Heuristic.
- **Live Explanation:** A "Console" or "Log" panel that explains what the algorithm is doing at each animation frame (e.g., "Finding nearest neighbor in Level 2...").
- **Complexity Analysis:** Display real-time stats like search hops and distance calculations.

## Technical Architecture
- **Framework:** React.js for the UI.
- **Visualization:** D3.js or React-Simple-Maps/Canvas API for graph rendering.
- **Logic:** TypeScript implementation of HNSW for the simulation engine.
- **Deployment:** Static site (GitHub Pages or Vercel).

## Implementation Phases
1. **Phase 1: Core Engine:** Implement the HNSW algorithm in TypeScript with hook-based state management.
2. **Phase 2: Basic Visualization:** Render nodes and edges for a single layer.
3. **Phase 3: Hierarchical View:** Add multi-layer support and layer switching.
4. **Phase 4: Animation & Step-Through:** Implement the control logic for pausing/stepping through algorithms.
5. **Phase 5: UI/UX & Polish:** Add parameter controls, explanations, and responsive design.
