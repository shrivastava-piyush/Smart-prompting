import { useState } from 'react'
import './App.css'
import { useHNSW } from './hooks/useHNSW'
import { GraphLayer } from './components/GraphLayer'
import { StackedGraph } from './components/StackedGraph'

function App() {
  const [M, setM] = useState(4);
  const [efConstruction, setEfConstruction] = useState(8);
  const { 
    nodes, 
    maxLevel, 
    currentStep, 
    isStepping, 
    addPoint, 
    startAddPointStep, 
    nextStep 
  } = useHNSW({ M, efConstruction });
  
  const [currentLevel, setCurrentLevel] = useState(0);
  const [viewMode, setViewMode] = useState<'single' | 'stacked'>('single');

  const handleAddRandomPoint = () => {
    const x = Math.random() * 800;
    const y = Math.random() * 600;
    addPoint([x, y], Math.random().toString(36).substring(7));
  };

  const handleStartStepAdd = () => {
    const x = Math.random() * 800;
    const y = Math.random() * 600;
    startAddPointStep([x, y], Math.random().toString(36).substring(7));
  };

  const getStepDescription = (step: any) => {
    switch (step.type) {
      case 'search_layer_start':
        return `Starting search on Level ${step.level} from Entry Point node ${step.entryPoint}.`;
      case 'search_layer_step':
        return `Evaluating node ${step.current} on Level ${step.level}. Current candidate set size: ${step.candidates.length}.`;
      case 'search_layer_end':
        return `Search finished on Level ${step.level}. Found nearest node: ${step.nearest}.`;
      case 'connect_nodes':
        return `Connecting new node to neighbor ${step.nodeB} on Level ${step.level}.`;
      case 'shrink_neighbors':
        return `Heuristic: Shrinking neighbors of node ${step.node} on Level ${step.level} to maintain degree constraints.`;
      default:
        return 'Executing algorithm...';
    }
  };

  return (
    <div className="App">
      <h1>HNSW Visualizer</h1>
      
      {!isStepping && (
        <div className="parameters">
          <label>M: </label>
          <input type="number" value={M} onChange={e => setM(Number(e.target.value))} min="2" max="16" />
          <label> efConstruction: </label>
          <input type="number" value={efConstruction} onChange={e => setEfConstruction(Number(e.target.value))} min="2" max="100" />
        </div>
      )}

      <div className="controls">
        {!isStepping ? (
          <>
            <button onClick={handleAddRandomPoint}>Quick Add Point</button>
            <button onClick={handleStartStepAdd}>Step-by-Step Add</button>
            <button onClick={() => setViewMode(viewMode === 'single' ? 'stacked' : 'single')}>
              Switch to {viewMode === 'single' ? 'Stacked' : 'Single'} View
            </button>
          </>
        ) : (
          <button onClick={nextStep} className="next-btn">Next Step</button>
        )}
        
        {viewMode === 'single' && (
          <div>
            <label>View Level: </label>
            <select 
              value={currentLevel} 
              onChange={(e) => setCurrentLevel(Number(e.target.value))}
            >
              {Array.from({ length: Math.max(0, maxLevel + 1) }, (_, i) => (
                <option key={i} value={i}>Level {i}</option>
              ))}
            </select>
          </div>
        )}
      </div>
      
      {isStepping && currentStep && (
        <div className="explanation">
          <h3>Current Action:</h3>
          <p>{getStepDescription(currentStep)}</p>
        </div>
      )}

      <div className="stats">
        <p>Nodes: {nodes.length}</p>
        <p>Max Level: {maxLevel}</p>
      </div>

      <div className="graph-container">
        {viewMode === 'single' ? (
          <GraphLayer 
            nodes={nodes} 
            level={currentLevel} 
            width={800} 
            height={600} 
            currentStep={currentStep}
            onLayerClick={(x, y) => isStepping ? null : startAddPointStep([x, y], Math.random().toString(36).substring(7))}
          />
        ) : (
          <StackedGraph 
            nodes={nodes} 
            maxLevel={maxLevel} 
            width={800} 
            height={600} 
          />
        )}
      </div>
    </div>
  )
}

export default App
