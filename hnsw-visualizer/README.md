# HNSW Interactive Visualizer

An interactive, browser-based tool for learning how **Hierarchical Navigable Small World (HNSW)** graphs work. This tool provides a visual playground to understand how high-dimensional vector search can be made efficient through multi-layer navigation.

## 🚀 Getting Started

To run the visualizer on your local machine:

```bash
cd hnsw-visualizer
npm install
npm run dev
```

The application will be available at `http://localhost:5173`.

## 🧠 What is HNSW?

HNSW is a state-of-the-art algorithm for **Approximate Nearest Neighbor (ANN)** search. It builds a hierarchical graph structure where:
- **Upper Layers** contain "express" connections between distant points, allowing for fast global navigation.
- **Lower Layers** contain denser connections between nearby points for precise local search.

## ✨ Key Features

### 1. Multi-Layer Visualization
- **Single View:** Focus on one level at a time (Level 0, Level 1, etc.).
- **Stacked View:** A perspective visualization showing how nodes at higher levels are "anchored" to their counterparts in the base layer.

### 2. Step-by-Step Learning
Click anywhere on the canvas or use the "Step-by-Step Add" button to watch the algorithm:
- Search for the entry point in upper layers.
- Evaluate candidates in the current layer.
- Apply the heuristic to select diverse neighbors.
- Shrink connections to maintain the graph's degree constraints.

### 3. Parameter Playground
Experiment with the two most critical HNSW parameters:
- **M (Max Connections):** Determines the maximum number of neighbors a node can have in each layer.
- **efConstruction:** Controls the trade-off between construction speed and search accuracy by defining the size of the dynamic candidate list.

## 🛠 Tech Stack
- **React + TypeScript:** For the UI and state management.
- **Vite:** For ultra-fast local development.
- **SVG Rendering:** For crisp, scalable graph visualizations.
- **Custom HNSW Engine:** A generator-based implementation that allows the UI to pause and explain every sub-step of the algorithm.
