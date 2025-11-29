import { useState } from 'react';
import { Utensils, Users, ClipboardList, Bell, Clock, ChefHat, Leaf, AlertTriangle } from 'lucide-react';
import StatCard from '@/components/ui/StatCard';
import { cn } from '@/lib/utils';

const inpatientMeals = [
  { id: 1, bed: 'W1-B01', patient: 'James Wilson', diet: 'Regular', allergies: [], nextMeal: 'Lunch', time: '12:00 PM', status: 'pending' },
  { id: 2, bed: 'W1-B02', patient: 'Emma Taylor', diet: 'Soft', allergies: ['Dairy'], nextMeal: 'Lunch', time: '12:00 PM', status: 'pending' },
  { id: 3, bed: 'W1-B03', patient: 'Michael Brown', diet: 'Diabetic', allergies: [], nextMeal: 'Lunch', time: '12:00 PM', status: 'preparing' },
  { id: 4, bed: 'W1-B04', patient: 'Lisa Anderson', diet: 'Low Sodium', allergies: ['Nuts', 'Shellfish'], nextMeal: 'Lunch', time: '12:00 PM', status: 'pending' },
  { id: 5, bed: 'W2-B01', patient: 'David Miller', diet: 'Regular', allergies: [], nextMeal: 'Lunch', time: '12:00 PM', status: 'delivered' },
];

const todayMenu = [
  { meal: 'Breakfast', items: ['Oatmeal with fruits', 'Scrambled eggs', 'Whole wheat toast', 'Fresh juice'], served: true },
  { meal: 'Lunch', items: ['Grilled chicken breast', 'Steamed vegetables', 'Brown rice', 'Fruit salad'], served: false },
  { meal: 'Dinner', items: ['Baked fish', 'Mashed potatoes', 'Green beans', 'Soup'], served: false },
];

const staffOrders = [
  { id: 1, staff: 'Dr. Sarah Johnson', items: 'Chicken Salad, Iced Tea', status: 'preparing', orderTime: '11:30 AM' },
  { id: 2, staff: 'Emily Williams', items: 'Vegetable Soup, Bread Roll', status: 'ready', orderTime: '11:25 AM' },
  { id: 3, staff: 'Michael Chen', items: 'Grilled Sandwich, Coffee', status: 'pending', orderTime: '11:35 AM' },
];

export default function CanteenDashboard() {
  const [selectedDietFilter, setSelectedDietFilter] = useState('all');

  return (
    <div className="space-y-6 animate-fade-in">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-heading font-bold">Kitchen Dashboard</h1>
          <p className="text-muted-foreground">Food Services & Dietary Management</p>
        </div>
        <div className="flex gap-3">
          <button className="btn-secondary">
            <ClipboardList className="w-4 h-4" />
            Menu Planning
          </button>
          <button className="btn-primary">
            <Utensils className="w-4 h-4" />
            New Order
          </button>
        </div>
      </div>

      {/* Stats */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        <StatCard
          title="Inpatient Meals"
          value={24}
          change="Next: Lunch 12:00 PM"
          changeType="neutral"
          icon={Utensils}
          iconColor="text-primary"
        />
        <StatCard
          title="Special Diets"
          value={8}
          change="Diabetic, Low Sodium, etc."
          changeType="neutral"
          icon={Leaf}
          iconColor="text-success"
        />
        <StatCard
          title="Staff Orders"
          value={12}
          change="5 pending"
          changeType="neutral"
          icon={ClipboardList}
          iconColor="text-warning"
        />
        <StatCard
          title="Dietary Alerts"
          value={4}
          change="Allergies to note"
          changeType="negative"
          icon={AlertTriangle}
          iconColor="text-critical"
        />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Inpatient Meal Schedule */}
        <div className="lg:col-span-2 card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Inpatient Meal Schedule</h2>
            <div className="flex gap-2">
              {['all', 'diabetic', 'soft', 'low sodium'].map((filter) => (
                <button
                  key={filter}
                  onClick={() => setSelectedDietFilter(filter)}
                  className={cn(
                    'px-3 py-1.5 rounded-lg text-xs font-medium transition-colors capitalize',
                    selectedDietFilter === filter
                      ? 'bg-primary text-primary-foreground'
                      : 'bg-muted text-muted-foreground hover:bg-muted/80'
                  )}
                >
                  {filter}
                </button>
              ))}
            </div>
          </div>
          <div className="divide-y divide-border">
            {inpatientMeals.map((meal) => (
              <div key={meal.id} className="p-4 hover:bg-muted/30 transition-colors">
                <div className="flex items-center justify-between">
                  <div className="flex items-center gap-4">
                    <div className="text-center px-3 py-2 bg-muted rounded-lg">
                      <p className="text-xs text-muted-foreground">Bed</p>
                      <p className="font-bold text-sm">{meal.bed}</p>
                    </div>
                    <div>
                      <div className="flex items-center gap-2">
                        <p className="font-medium">{meal.patient}</p>
                        {meal.allergies.length > 0 && (
                          <span className="badge-critical flex items-center gap-1">
                            <AlertTriangle className="w-3 h-3" />
                            Allergies
                          </span>
                        )}
                      </div>
                      <div className="flex items-center gap-2 mt-1">
                        <span className="badge-info">{meal.diet}</span>
                        {meal.allergies.length > 0 && (
                          <span className="text-xs text-critical">{meal.allergies.join(', ')}</span>
                        )}
                      </div>
                    </div>
                  </div>
                  <div className="flex items-center gap-4">
                    <div className="text-right">
                      <p className="text-sm font-medium">{meal.nextMeal}</p>
                      <p className="text-xs text-muted-foreground">{meal.time}</p>
                    </div>
                    <span className={cn(
                      'badge-status',
                      meal.status === 'pending' && 'bg-muted text-muted-foreground',
                      meal.status === 'preparing' && 'badge-warning',
                      meal.status === 'delivered' && 'badge-success'
                    )}>
                      {meal.status}
                    </span>
                    <button className="btn-primary text-sm py-1.5">
                      {meal.status === 'pending' ? 'Prepare' : meal.status === 'preparing' ? 'Ready' : 'View'}
                    </button>
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>

        {/* Today's Menu */}
        <div className="card-medical">
          <div className="p-5 border-b border-border flex items-center justify-between">
            <h2 className="font-semibold">Today's Menu</h2>
            <ChefHat className="w-5 h-5 text-muted-foreground" />
          </div>
          <div className="divide-y divide-border">
            {todayMenu.map((menu) => (
              <div key={menu.meal} className="p-4">
                <div className="flex items-center justify-between mb-2">
                  <p className="font-semibold">{menu.meal}</p>
                  {menu.served ? (
                    <span className="badge-success">Served</span>
                  ) : (
                    <span className="badge-info">Upcoming</span>
                  )}
                </div>
                <ul className="space-y-1">
                  {menu.items.map((item, idx) => (
                    <li key={idx} className="text-sm text-muted-foreground flex items-center gap-2">
                      <span className="w-1.5 h-1.5 rounded-full bg-primary" />
                      {item}
                    </li>
                  ))}
                </ul>
              </div>
            ))}
          </div>
          <div className="p-4 border-t border-border">
            <button className="btn-secondary w-full">
              <ClipboardList className="w-4 h-4" />
              Edit Menu
            </button>
          </div>
        </div>
      </div>

      {/* Staff Orders */}
      <div className="card-medical p-5">
        <div className="flex items-center justify-between mb-4">
          <h2 className="font-semibold">Staff Orders</h2>
          <span className="badge-info">{staffOrders.length} active</span>
        </div>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
          {staffOrders.map((order) => (
            <div key={order.id} className="p-4 bg-muted/30 rounded-lg">
              <div className="flex items-center justify-between mb-2">
                <span className={cn(
                  'badge-status',
                  order.status === 'pending' && 'bg-muted text-muted-foreground',
                  order.status === 'preparing' && 'badge-warning',
                  order.status === 'ready' && 'badge-success'
                )}>
                  {order.status}
                </span>
                <span className="text-xs text-muted-foreground">{order.orderTime}</span>
              </div>
              <p className="font-medium">{order.staff}</p>
              <p className="text-sm text-muted-foreground mt-1">{order.items}</p>
              <button className="btn-ghost text-xs mt-3 w-full">
                {order.status === 'ready' ? 'Mark Delivered' : 'Update Status'}
              </button>
            </div>
          ))}
        </div>
      </div>
    </div>
  );
}
